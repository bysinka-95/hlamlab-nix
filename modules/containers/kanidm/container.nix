{ config, ... }:
let
  vars = import ../../common/local.nix;
in
{
  containers.kanidm = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.5";

    bindMounts = {
      "/var/lib/kanidm" = {
        hostPath = "/var/lib/services/kanidm";
        isReadOnly = false;
      };
      "/run/secrets/kanidm-admin-password" = {
        hostPath = config.sops.secrets.kanidm-admin-password.path;
        isReadOnly = true;
      };
      "/run/secrets/immich-oidc-client-secret" = {
        hostPath = config.sops.secrets.immich-oidc-client-secret.path;
        isReadOnly = true;
      };
    };

    config = { pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 8443 ];

      # Self-signed certs for Kanidm (required even behind proxy)
      systemd.services.kanidm.preStart = ''
        if [ ! -f /var/lib/kanidm/key.pem ]; then
          ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 \
            -keyout /var/lib/kanidm/key.pem \
            -out /var/lib/kanidm/chain.pem \
            -days 3650 -nodes \
            -subj "/CN=auth.${vars.domain}"
          chown kanidm:kanidm /var/lib/kanidm/*.pem
        fi
      '';

      services.kanidm = {
        package = pkgs.kanidm_1_x.withSecretProvisioning;
        server.settings = {
          domain = "auth.${vars.domain}";
          origin = "https://auth.${vars.domain}";
          bindaddress = "0.0.0.0:8443";
          
          trust_x_forward_for = true;
          
          tls_chain = "/var/lib/kanidm/chain.pem";
          tls_key = "/var/lib/kanidm/key.pem";
        };

        # Declarative provisioning
        provision = {
          enable = true;
          instanceUrl = "https://127.0.0.1:8443";
          acceptInvalidCerts = true;
          idmAdminPasswordFile = "/run/secrets/kanidm-admin-password";

          persons = {
            admin_user = {
              displayName = "Admin User";
              mailAddresses = [ "admin@${vars.domain}" ];
              groups = [ "admin" ];
            };
          };

          groups = {
            admin = {};
          };

          systems.oauth2 = {
            immich = {
              displayName = "Immich";
              originUrl = [
                "https://immich.${vars.domain}/auth/login"
                "app.immich:/"
                "app.immich://auth/login"
              ];
              basicSecretFile = "/run/secrets/immich-oidc-client-secret";
              public = false;
              originLanding = "https://immich.${vars.domain}";
            };
            opencloud = {
              displayName = "OpenCloud";
              originUrl = "https://opencloud.${vars.domain}/core/oidc/login";
              public = true;
              preferShortUsername = true;
              originLanding = "https://opencloud.${vars.domain}";
            };
          };
        };
      };

      system.stateVersion = "25.11";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/kanidm 0755 root root -"
  ];
}
