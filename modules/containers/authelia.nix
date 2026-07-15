{ lib, config, ... }:
let
  hostConfig = config;
in
{
  hlamlab.services.authelia = {
    ip = lib.mkDefault "10.0.0.5";
    port = lib.mkDefault 9091;
    domainPrefix = lib.mkDefault "auth";
    storageQuota = lib.mkDefault "10G";
    storageReservation = lib.mkDefault "1G";

    cpuLimit = lib.mkDefault "100%";
    ramLimit = lib.mkDefault "1G";
    ramHigh = lib.mkDefault "512M";

    nameservers = [ "1.1.1.1" "1.0.0.1" ];

    serviceUser = "authelia-main";

    bindMounts = {
      "/var/lib/authelia-main" = {
        hostPath = "/var/lib/services/authelia";
        isReadOnly = false;
      };
    };

    secrets = {
      authelia-jwt-secret = {
        key = "authelia/jwt-secret";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-session-secret = {
        key = "authelia/session-secret";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-storage-encryption-key = {
        key = "authelia/storage-encryption-key";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-immich-oidc-client-secret = {
        key = "immich/oidc-client-secret";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-lldap-user-pass = {
        key = "lldap/user-pass";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-vaultwarden-oidc-client-secret = {
        key = "vaultwarden/oidc-client-secret";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-oidc-hmac-secret = {
        key = "authelia/oidc-hmac-secret";
        restartUnits = [ "authelia-main.service" ];
      };
      authelia-oidc-issuer-private-key = {
        key = "authelia/oidc-issuer-private-key";
        restartUnits = [ "authelia-main.service" ];
      };
    };

    containerConfig = { config, pkgs, ... }: {
      services.redis.servers.authelia.enable = true;

      services.authelia.instances.main = {
        enable = true;

        secrets = {
          jwtSecretFile = config.sops.secrets.authelia-jwt-secret.path;
          sessionSecretFile = config.sops.secrets.authelia-session-secret.path;
          storageEncryptionKeyFile = config.sops.secrets.authelia-storage-encryption-key.path;
          oidcHmacSecretFile = config.sops.secrets.authelia-oidc-hmac-secret.path;
          oidcIssuerPrivateKeyFile = config.sops.secrets.authelia-oidc-issuer-private-key.path;
        };

        environmentVariables = {
          X_AUTHELIA_CONFIG_FILTERS = "template";
          AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = config.sops.secrets.authelia-lldap-user-pass.path;
        };

        settings = {
          theme = "auto";
          default_2fa_method = "totp";

          server = {
            address = "tcp://0.0.0.0:9091/";
          };

          log = {
            level = "info";
          };

          authentication_backend = {
            ldap = {
              implementation = "lldap";
              address = "ldap://10.0.0.6:3890";
              base_dn = hostConfig.hlamlab.settings.ldapBaseDn;
              user = "uid=admin,ou=people,${hostConfig.hlamlab.settings.ldapBaseDn}";
            };
          };

          access_control = {
            default_policy = "deny";
            rules = [
              {
                domain = "*.${hostConfig.hlamlab.settings.domain}";
                policy = "one_factor";
              }
            ];
          };

          session = {
            name = "authelia_session";
            cookies = [
              {
                domain = hostConfig.hlamlab.settings.domain;
                authelia_url = "https://auth.${hostConfig.hlamlab.settings.domain}";
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
              clients = [
                {
                  client_id = "immich";
                  client_name = "Immich";
                  client_secret = "$plaintext\${{ secret \"${config.sops.secrets.authelia-immich-oidc-client-secret.path}\" }}";
                  public = false;
                  authorization_policy = "one_factor";
                  redirect_uris = [
                    "https://immich.${hostConfig.hlamlab.settings.domain}/auth/login"
                    "app.immich:///oauth-callback"
                  ];
                  scopes = [ "openid" "profile" "email" ];
                  userinfo_signed_response_alg = "none";
                  token_endpoint_auth_method = "client_secret_post";
                }
                {
                  client_id = "opencloud";
                  client_name = "OpenCloud";
                  public = true;
                  authorization_policy = "one_factor";
                  redirect_uris = [
                    "https://opencloud.${hostConfig.hlamlab.settings.domain}/"
                    "https://opencloud.${hostConfig.hlamlab.settings.domain}/oidc-callback.html"
                    "https://opencloud.${hostConfig.hlamlab.settings.domain}/oidc-silent-redirect.html"
                  ];
                  scopes = [ "openid" "profile" "email" "groups" ];
                  userinfo_signed_response_alg = "none";
                  access_token_signed_response_alg = "RS256";
                }
                {
                  client_id = "vaultwarden";
                  client_name = "Vaultwarden";
                  client_secret = "$plaintext\${{ secret \"${config.sops.secrets.authelia-vaultwarden-oidc-client-secret.path}\" }}";
                  public = false;
                  authorization_policy = "one_factor";
                  redirect_uris = [
                    "https://vault.${hostConfig.hlamlab.settings.domain}/identity/connect/oidc-signin"
                  ];
                  scopes = [ "openid" "profile" "email" "offline_access" ];
                  userinfo_signed_response_alg = "none";
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
        StateDirectory = "authelia-main";
      };
    };
  };

  # Set host directory permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/services/authelia 0750 root root -"
  ];
}
