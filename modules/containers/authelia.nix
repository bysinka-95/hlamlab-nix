{ config, ... }:
let
  settings = config.hlamlab.settings;
  svc = config.hlamlab.services;
in
{
  hlamlab.services.authelia = {
    ip = "10.0.0.5";
    port = 9091;
    domainPrefix = "auth";

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
      authelia-immich-oidc-client-secret = {
        key = "immich/oidc-client-secret";
        unit = "authelia-main.service";
      };
      authelia-lldap-user-pass = {
        key = "lldap/user-pass";
        unit = "authelia-main.service";
      };
      authelia-vaultwarden-oidc-client-secret = {
        key = "vaultwarden/oidc-client-secret";
        unit = "authelia-main.service";
      };
      authelia-grafana-oidc-client-secret = {
        key = "grafana/oidc-client-secret";
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
          AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = svc.authelia.secrets.authelia-lldap-user-pass.path;
        };

        settings = {
          theme = "auto";
          default_2fa_method = "totp";

          server = {
            address = "tcp://0.0.0.0:${toString svc.authelia.port}/";
          };

          log = {
            level = "info";
          };

          telemetry = {
            metrics = {
              enabled = true;
              address = "tcp://0.0.0.0:9959/";
            };
          };

          authentication_backend = {
            ldap = {
              implementation = "lldap";
              address = "ldap://${svc.lldap.ip}:3890";
              base_dn = settings.ldapBaseDn;
              user = "uid=admin,ou=people,${settings.ldapBaseDn}";
            };
          };

          # Immich and OpenCloud take their admin role from these claims, in
          # each one's own vocabulary; members of `admins` (declared in
          # lldap.nix) get the admin value.
          definitions.user_attributes.immich_role.expression = ''"admins" in groups ? "admin" : "user"'';
          definitions.user_attributes.opencloud_role.expression = ''"admins" in groups ? "opencloudAdmin" : "opencloudUser"'';

          access_control = {
            default_policy = "deny";
            rules = [
              {
                domain = "*.${settings.domain}";
                policy = "one_factor";
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
              clients = [
                {
                  client_id = "immich";
                  client_name = "Immich";
                  claims_policy = "immich";
                  client_secret = "$plaintext\${{ secret \"${svc.authelia.secrets.authelia-immich-oidc-client-secret.path}\" }}";
                  public = false;
                  authorization_policy = "one_factor";
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
                  authorization_policy = "one_factor";
                  redirect_uris = [
                    "${svc.opencloud.baseUrl}/"
                    "${svc.opencloud.baseUrl}/oidc-callback.html"
                    "${svc.opencloud.baseUrl}/oidc-silent-redirect.html"
                  ];
                  scopes = [ "openid" "profile" "email" "groups" "opencloud_role" ];
                  userinfo_signed_response_alg = "none";
                  access_token_signed_response_alg = "RS256";
                }
                {
                  client_id = "vaultwarden";
                  client_name = "Vaultwarden";
                  client_secret = "$plaintext\${{ secret \"${svc.authelia.secrets.authelia-vaultwarden-oidc-client-secret.path}\" }}";
                  public = false;
                  authorization_policy = "one_factor";
                  redirect_uris = [
                    "${svc.vaultwarden.baseUrl}/identity/connect/oidc-signin"
                  ];
                  scopes = [ "openid" "profile" "email" "offline_access" ];
                  userinfo_signed_response_alg = "none";
                  token_endpoint_auth_method = "client_secret_basic";
                }
                {
                  client_id = "grafana";
                  client_name = "Grafana";
                  claims_policy = "grafana";
                  client_secret = "$plaintext\${{ secret \"${svc.authelia.secrets.authelia-grafana-oidc-client-secret.path}\" }}";
                  public = false;
                  authorization_policy = "one_factor";
                  redirect_uris = [
                    "${svc.grafana.baseUrl}/login/generic_oauth"
                  ];
                  scopes = [ "openid" "profile" "email" "groups" ];
                  userinfo_signed_response_alg = "none";
                  access_token_signed_response_alg = "RS256";
                  token_endpoint_auth_method = "client_secret_basic";
                }
              ];
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

}
