{ config, lib, ... }:
let
  settings = config.hlamlab.settings;
  svc = config.hlamlab.services;
in
{
  hlamlab.services.authelia = {
    ip = "10.0.0.5";
    port = 9091;
    domainPrefix = "auth";

    # The user directory. Everything else Authelia talks to comes to it.
    talksTo.lldap = [ 3890 ];

    # The NixOS module names the instance's unit and state dir after the
    # instance, not the service.
    serviceUser = "authelia-main";
    dataDir = "/var/lib/authelia-main";

    # The module's own `secrets.*File` are LoadCredential-ed by systemd (root),
    # so they need no unit. Template `{{ secret }}` and `_FILE` env vars are
    # read by Authelia itself, hence `unit`.
    secrets = {
      authelia-jwt-secret = {
        key = "authelia/jwt-secret";
      };
      authelia-session-secret = {
        key = "authelia/session-secret";
      };
      authelia-storage-encryption-key = {
        key = "authelia/storage-encryption-key";
      };
      # Authelia's own read-only LLDAP bind user (declared in lldap.nix).
      authelia-ldap-password = {
        key = "authelia/ldap-password";
        unit = "authelia-main.service";
      };
      # pbkdf2-sha512 digests of the OIDC client secrets: the plaintext lives
      # only in each client's own container.
      authelia-immich-oidc-digest = {
        key = "authelia/immich-oidc-digest";
        unit = "authelia-main.service";
      };
      authelia-vaultwarden-oidc-digest = {
        key = "authelia/vaultwarden-oidc-digest";
        unit = "authelia-main.service";
      };
      authelia-grafana-oidc-digest = {
        key = "authelia/grafana-oidc-digest";
        unit = "authelia-main.service";
      };
    } // lib.optionalAttrs svc.gotify.enable {
      authelia-gotify-oidc-digest = {
        key = "authelia/gotify-oidc-digest";
        unit = "authelia-main.service";
      };
      authelia-oidc-hmac-secret = {
        key = "authelia/oidc-hmac-secret";
      };
      authelia-oidc-issuer-private-key = {
        key = "authelia/oidc-issuer-private-key";
      };
    };

    containerConfig = { config, ... }: {
      # Prometheus metrics endpoint (scraped at 10.0.0.5:9959).
      networking.firewall.allowedTCPPorts = [ 9959 ];

      services.redis.servers.authelia.enable = true;

      services.authelia.instances.main = {
        enable = true;

        secrets = {
          jwtSecretFile = svc.authelia.secrets.authelia-jwt-secret.path;
          sessionSecretFile = svc.authelia.secrets.authelia-session-secret.path;
          storageEncryptionKeyFile = svc.authelia.secrets.authelia-storage-encryption-key.path;
          oidcHmacSecretFile = svc.authelia.secrets.authelia-oidc-hmac-secret.path;
          oidcIssuerPrivateKeyFile = svc.authelia.secrets.authelia-oidc-issuer-private-key.path;
        };

        environmentVariables = {
          X_AUTHELIA_CONFIG_FILTERS = "template";
          AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = svc.authelia.secrets.authelia-ldap-password.path;
        };

        settings = {
          theme = "auto";
          default_2fa_method = "totp";

          # No internet egress. Containers share the host's clock anyway.
          ntp.disable_startup_check = true;

          server = {
            address = "tcp://0.0.0.0:${toString svc.authelia.port}/";
          };

          log = {
            level = "info";
          };

          telemetry = {
            metrics = {
              enabled = true;
              # The path is part of the address; Prometheus scrapes /metrics.
              address = "tcp://0.0.0.0:9959/metrics";
            };
          };

          authentication_backend = {
            ldap = {
              implementation = "lldap";
              address = "ldap://${svc.lldap.ip}:3890";
              base_dn = settings.ldapBaseDn;
              # Read-only bind user (group lldap_strict_readonly), not the
              # LLDAP admin. Password resets happen in the LLDAP UI.
              user = "uid=authelia,ou=people,${settings.ldapBaseDn}";
            };
            # The notifier is a file; users reset passwords in the LLDAP UI.
            password_reset.disable = true;
          };

          # Immich and OpenCloud take their admin role from these claims, in
          # each one's own vocabulary; members of `admins` (declared in
          # lldap.nix) get the admin value.
          definitions.user_attributes.immich_role.expression = ''"admins" in groups ? "admin" : "user"'';
          definitions.user_attributes.opencloud_role.expression = ''"admins" in groups ? "opencloudAdmin" : "opencloudUser"'';

          # Only the admin UIs sit behind the `authelia` middleware; the apps
          # authenticate through OIDC (authorization_policy on each client).
          access_control = {
            default_policy = "deny";
            rules = [
              {
                domain = [ svc.lldap.fqdn "traefik.${settings.domain}" ];
                policy = "two_factor";
                subject = [ "group:admins" ];
              }
              {
                domain = svc.vaultwarden.fqdn;
                resources = [ "^/admin([/?].*)?$" ];
                policy = "two_factor";
                subject = [ "group:admins" ];
              }
            ];
          };

          session = {
            name = "authelia_session";
            cookies = [
              {
                domain = settings.domain;
                authelia_url = svc.authelia.baseUrl;
              }
            ];
            redis = {
              host = config.services.redis.servers.authelia.unixSocket;
            };
          };

          storage = {
            local = {
              path = "/var/lib/authelia-main/db.sqlite3";
            };
          };

          notifier = {
            filesystem = {
              filename = "/var/lib/authelia-main/notification.txt";
            };
          };

          identity_providers = {
            oidc = {
              cors = {
                endpoints = [ "authorization" "token" "revocation" "introspection" ];
                allowed_origins_from_client_redirect_uris = true;
              };
              claims_policies = {
                grafana.id_token = [ "preferred_username" "email" "name" "groups" ];
                immich.custom_claims.immich_role = { };
                opencloud.custom_claims.opencloud_role = { };
              };
              scopes.immich_role.claims = [ "immich_role" ];
              scopes.opencloud_role.claims = [ "opencloud_role" ];
              # Every client is ours, declared here with fixed redirect URIs, so
              # a consent screen guards nothing. Implicit consent also lets
              # OpenCloud's web app sign in silently: it does so in a hidden
              # iframe, and the consent page refuses to be framed.
              clients = [
                {
                  client_id = "immich";
                  client_name = "Immich";
                  claims_policy = "immich";
                  client_secret = ''{{ secret "${svc.authelia.secrets.authelia-immich-oidc-digest.path}" }}'';
                  public = false;
                  authorization_policy = "two_factor";
                  consent_mode = "implicit";
                  redirect_uris = [
                    "${svc.immich.baseUrl}/auth/login"
                    "app.immich:///oauth-callback"
                  ];
                  scopes = [ "openid" "profile" "email" "immich_role" ];
                  userinfo_signed_response_alg = "none";
                  token_endpoint_auth_method = "client_secret_post";
                }
                {
                  client_id = "opencloud";
                  client_name = "OpenCloud";
                  claims_policy = "opencloud";
                  public = true;
                  authorization_policy = "two_factor";
                  consent_mode = "implicit";
                  redirect_uris = [
                    "${svc.opencloud.baseUrl}/"
                    "${svc.opencloud.baseUrl}/oidc-callback.html"
                    "${svc.opencloud.baseUrl}/oidc-silent-redirect.html"
                  ];
                  scopes = [ "openid" "profile" "email" "groups" "opencloud_role" ];
                  userinfo_signed_response_alg = "none";
                  # OpenCloud's proxy verifies access tokens as JWTs. RFC 9068
                  # wants them to name their recipient, so every token for this
                  # client carries OpenCloud as `aud`.
                  access_token_signed_response_alg = "RS256";
                  audience = [ svc.opencloud.baseUrl ];
                  requested_audience_mode = "implicit";
                }
                {
                  client_id = "vaultwarden";
                  client_name = "Vaultwarden";
                  client_secret = ''{{ secret "${svc.authelia.secrets.authelia-vaultwarden-oidc-digest.path}" }}'';
                  public = false;
                  authorization_policy = "two_factor";
                  consent_mode = "implicit";
                  redirect_uris = [
                    "${svc.vaultwarden.baseUrl}/identity/connect/oidc-signin"
                  ];
                  scopes = [ "openid" "profile" "email" "offline_access" ];
                  # `offline_access` is only honoured with the refresh_token
                  # grant; without it Vaultwarden gets no refresh token and
                  # cannot renew its SSO session.
                  response_types = [ "code" ];
                  grant_types = [ "authorization_code" "refresh_token" ];
                  userinfo_signed_response_alg = "none";
                  token_endpoint_auth_method = "client_secret_basic";
                }
                {
                  client_id = "grafana";
                  client_name = "Grafana";
                  claims_policy = "grafana";
                  client_secret = ''{{ secret "${svc.authelia.secrets.authelia-grafana-oidc-digest.path}" }}'';
                  public = false;
                  authorization_policy = "two_factor";
                  consent_mode = "implicit";
                  redirect_uris = [
                    "${svc.grafana.baseUrl}/login/generic_oauth"
                  ];
                  scopes = [ "openid" "profile" "email" "groups" ];
                  userinfo_signed_response_alg = "none";
                  # Opaque access token (the default). Grafana reads its claims
                  # from the ID token; a signed JWT here would also pass at any
                  # service that accepts Authelia's JWTs — OpenCloud included.
                  token_endpoint_auth_method = "client_secret_basic";
                }
              ] ++ lib.optional svc.gotify.enable {
                client_id = "gotify";
                client_name = "Gotify";
                client_secret = ''{{ secret "${svc.authelia.secrets.authelia-gotify-oidc-digest.path}" }}'';
                public = false;
                authorization_policy = "two_factor";
                consent_mode = "implicit";
                redirect_uris = [
                  "${svc.gotify.baseUrl}/auth/oidc/callback"
                  # The Android app: Gotify passes it on and exchanges the code itself.
                  "gotify://oidc/callback"
                ];
                scopes = [ "openid" "profile" "email" "groups" ];
                require_pkce = true;
                pkce_challenge_method = "S256";
                userinfo_signed_response_alg = "none";
                token_endpoint_auth_method = "client_secret_basic";
              };
            };
          };
        };
      };

      systemd.services.authelia-main.serviceConfig = {
        SupplementaryGroups = [ config.services.redis.servers.authelia.group ];
        ReadWritePaths = [ "/var/lib/authelia-main" ];
      };
    };
  };

  # The gate for the admin UIs (rules in access_control above). Traefik asks
  # Authelia directly over the private network.
  services.traefik.dynamicConfigOptions.http.middlewares.authelia.forwardAuth = {
    address = "http://${svc.authelia.address}/api/authz/forward-auth";
    trustForwardHeader = true;
    authResponseHeaders = [ "Remote-User" "Remote-Groups" "Remote-Email" "Remote-Name" ];
    # Authelia only answers with a short redirect or error page.
    maxResponseBodySize = 65536;
  };
}
