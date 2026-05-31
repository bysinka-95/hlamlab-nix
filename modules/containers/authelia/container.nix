{ config, ... }:
let
  vars = import ../../common/local.nix;
in
{
  containers.authelia = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.5";

    bindMounts = {
      "/var/lib/authelia-main" = {
        hostPath = "/var/lib/services/authelia";
        isReadOnly = false;
      };
      "/run/secrets/authelia-jwt-secret" = {
        hostPath = config.sops.secrets.authelia-jwt-secret.path;
        isReadOnly = true;
      };
      "/run/secrets/authelia-session-secret" = {
        hostPath = config.sops.secrets.authelia-session-secret.path;
        isReadOnly = true;
      };
      "/run/secrets/authelia-storage-encryption-key" = {
        hostPath = config.sops.secrets.authelia-storage-encryption-key.path;
        isReadOnly = true;
      };
      "/run/secrets/authelia-immich-oidc-client-secret" = {
        hostPath = config.sops.secrets.authelia-immich-oidc-client-secret.path;
        isReadOnly = true;
      };
      "/run/secrets/authelia-oidc-hmac-secret" = {
        hostPath = config.sops.secrets.authelia-oidc-hmac-secret.path;
        isReadOnly = true;
      };
      "/run/secrets/authelia-oidc-issuer-private-key" = {
        hostPath = config.sops.secrets.authelia-oidc-issuer-private-key.path;
        isReadOnly = true;
      };
      "/run/secrets/authelia-admin-password" = {
        hostPath = config.sops.secrets.authelia-admin-password.path;
        isReadOnly = true;
      };
    };

    config = { config, pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 9091 ];
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

      users.users.authelia-main = {
        isSystemUser = true;
        group = "authelia-main";
        description = "Authelia main instance user";
        uid = 900;
      };

      users.groups.authelia-main = {
        gid = 900;
      };

      services.redis.servers.authelia.enable = true;

      services.authelia.instances.main = {
        enable = true;

        secrets = {
          jwtSecretFile = "/run/secrets/authelia-jwt-secret";
          sessionSecretFile = "/run/secrets/authelia-session-secret";
          storageEncryptionKeyFile = "/run/secrets/authelia-storage-encryption-key";
          oidcHmacSecretFile = "/run/secrets/authelia-oidc-hmac-secret";
          oidcIssuerPrivateKeyFile = "/run/secrets/authelia-oidc-issuer-private-key";
        };

        environmentVariables = {
          X_AUTHELIA_CONFIG_FILTERS = "template";
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
            file = {
              path = "/var/lib/authelia-main/users_database.yml";
            };
          };

          access_control = {
            default_policy = "deny";
            rules = [
              {
                domain = "*.${vars.domain}";
                policy = "one_factor";
              }
            ];
          };

          session = {
            name = "authelia_session";
            cookies = [
              {
                domain = vars.domain;
                authelia_url = "https://auth.${vars.domain}";
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
                  client_secret = "$plaintext\${{ secret \"/run/secrets/authelia-immich-oidc-client-secret\" }}";
                  public = false;
                  authorization_policy = "one_factor";
                  redirect_uris = [
                    "https://immich.${vars.domain}/auth/login"
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
                    "https://opencloud.${vars.domain}/"
                    "https://opencloud.${vars.domain}/oidc-callback.html"
                    "https://opencloud.${vars.domain}/oidc-silent-redirect.html"
                  ];
                  scopes = [ "openid" "profile" "email" "groups" ];
                  userinfo_signed_response_alg = "none";
                  access_token_signed_response_alg = "RS256";
                }
              ];
            };
          };
        };
      };

      systemd.services.authelia-main.preStart = pkgs.lib.mkBefore ''
        if ! ${pkgs.gnugrep}/bin/grep -q "^  admin:" /var/lib/authelia-main/users_database.yml 2>/dev/null; then
          # Generate hash from the plaintext password in SOPS, extracting the last space-delimited string (the hash)
          HASH=$(${pkgs.authelia}/bin/authelia crypto hash generate pbkdf2 --password "$(cat /run/secrets/authelia-admin-password)" | ${pkgs.gnugrep}/bin/grep '\$' | ${pkgs.gawk}/bin/awk '{print $NF}')

          cat <<EOF > /var/lib/authelia-main/users_database.yml
users:
  admin:
    displayname: "Administrator"
    password: "$HASH"
    email: admin@${vars.domain}
    groups:
      - admins
EOF
          chmod 0600 /var/lib/authelia-main/users_database.yml
        fi
      '';

      systemd.services.authelia-main.serviceConfig = {
        SupplementaryGroups = [ config.services.redis.servers.authelia.group ];
        ReadWritePaths = [ "/var/lib/authelia-main" ];
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/authelia-main 0750 authelia-main authelia-main -"
      ];

      system.stateVersion = "26.05";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/authelia 0750 900 900 -"
  ];
}
