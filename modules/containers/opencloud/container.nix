{ config, inputs, ... }:
let
  vars = import ../../common/settings.nix;
in
{
  # Native NixOS container running OpenCloud
  containers.opencloud = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1"; # host side of the veth
    localAddress = "10.0.0.2"; # container IP

    # Bind mount: Host storage → Container storage
    bindMounts = {
      "/var/lib/opencloud" = {
        hostPath = "/var/lib/services/opencloud";
        isReadOnly = false;
      };
      "/var/lib/sops-nix/key.txt" = {
        hostPath = "/var/lib/sops-nix/key.txt";
        isReadOnly = true;
      };
    };

    config = { lib, pkgs, config, ... }: {
      networking.firewall.allowedTCPPorts = [ 9200 9300 ];
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

      imports = [
        inputs.sops-nix.nixosModules.sops
      ];

      sops = {
        defaultSopsFile = ../../secrets/secrets.yaml;
        defaultSopsFormat = "yaml";
        age.keyFile = "/var/lib/sops-nix/key.txt";

        secrets = {
          opencloud-sharing-secret = {
            key = "opencloud/sharing-secret";
            owner = "opencloud";
            group = "opencloud";
            mode = "0400";
            restartUnits = [ "opencloud.service" ];
          };
        };
      };

      users.users.opencloud = {
        isSystemUser = true;
        group = "opencloud";
        description = "OpenCloud daemon user";
      };
      users.groups.opencloud = { };

      services.opencloud = {
        enable = true;
        url = "https://opencloud.${vars.domain}"; # Public URL for proper operation behind Traefik
        address = "0.0.0.0";
        port = 9200;
        environmentFile = config.sops.secrets.opencloud-sharing-secret.path;
        environment = {
          PROXY_TLS = "false";
          INITIAL_ADMIN_PASSWORD = "admin";

          OC_ADD_RUN_SERVICES = "collaboration";

          COLLABORATION_APP_NAME = "Office";
          COLLABORATION_APP_PRODUCT = "Collabora";
          COLLABORATION_APP_ADDR = "https://collabora.${vars.domain}";
          COLLABORATION_APP_INSECURE = "false";
          COLLABORATION_WOPI_SRC = "https://opencloud.${vars.domain}";
          COLLABORATION_APP_PROOF_DISABLE = "true";

          # Native OIDC integration with Authelia.
          OC_OIDC_ISSUER = "https://auth.${vars.domain}";
          OC_OIDC_CLIENT_ID = "opencloud";
          WEB_OIDC_CLIENT_ID = "opencloud";
          WEB_OIDC_SCOPE = "openid profile email groups";
          PROXY_OIDC_REWRITE_WELLKNOWN = "true";
          PROXY_AUTOPROVISION_ACCOUNTS = "true";

          # Keeps OpenCloud CSP IDP placeholders aligned with Authelia.
          IDP_DOMAIN = "auth.${vars.domain}";
        };
        settings = {
          # Workaround to fix https://github.com/nixos/nixpkgs/issues/523669
          sharing.service_account.service_account_id = "fb60052c-2854-4225-9ef9-acf6e7907ed1";

          csp = {
            directives = {
              child-src = [ "'self'" ];
              connect-src = [
                "'self'"
                "blob:"
                "https://\${COMPANION_DOMAIN|companion.opencloud.test}\${TRAEFIK_PORT_HTTPS}/"
                "wss://\${COMPANION_DOMAIN|companion.opencloud.test}\${TRAEFIK_PORT_HTTPS}/"
                "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                "https://\${IDP_DOMAIN|auth.${vars.domain}}\${TRAEFIK_PORT_HTTPS}/"
                "https://update.opencloud.eu/"
              ];
              default-src = [ "'none'" ];
              font-src = [ "'self'" ];
              frame-ancestors = [ "'self'" ];
              frame-src = [
                "'self'"
                "blob:"
                "https://embed.diagrams.net/"
                "https://collabora.${vars.domain}"
                "https://docs.opencloud.eu"
              ];
              img-src = [
                "'self'"
                "data:"
                "blob:"
                "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                "https://tile.openstreetmap.org/"
                "https://collabora.${vars.domain}/"
              ];
              manifest-src = [ "'self'" ];
              media-src = [ "'self'" ];
              object-src = [ "'self'" "blob:" ];
              script-src = [
                "'self'"
                "'unsafe-inline'"
                "https://\${IDP_DOMAIN|auth.${vars.domain}}\${TRAEFIK_PORT_HTTPS}/"
              ];
              style-src = [ "'self'" "'unsafe-inline'" ];
            };
          };

          proxy.csp_config_file_location = "/etc/opencloud/csp.yaml";
        };
      };

      systemd.services.opencloud.serviceConfig.StateDirectory = "opencloud";

      system.stateVersion = "26.05";
    };
  };

  # Create the host directory for OpenCloud state storage
  systemd.tmpfiles.rules = [
    "d /var/lib/services 0755 root root -"
    "d /var/lib/services/opencloud 0755 root root -"
  ];
}
