{ ... }:
let
  vars = import ../../common/settings.nix;
in
{
  hlamlab.services.opencloud = {
    ip = "10.0.0.2";
    port = 9200;
    domainPrefix = "opencloud";
    storageQuota = "50G";
    storageReservation = "10G";
    
    bindMounts = {
      "/var/lib/opencloud" = {
        hostPath = "/var/lib/services/opencloud";
        isReadOnly = false;
      };
    };

    traefikMiddlewares = [ "opencloud-headers" ];

    resourceLimits = {
      CPUQuota = "100%";
      CPUWeight = 100;
      MemoryMax = "2G";
      MemoryHigh = "1.5G";
      MemorySwapMax = "0B";
      IOWeight = 100;
      TasksMax = 512;
    };

    secrets = {
      opencloud-sharing-secret = {
        key = "opencloud/sharing-secret";
        restartUnits = [ "opencloud.service" ];
      };
    };

    containerConfig = { lib, pkgs, config, ... }: {
      networking.firewall.allowedTCPPorts = [ 9300 ];

      services.opencloud = {
        enable = true;
        url = "https://opencloud.${vars.domain}";
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

          OC_OIDC_ISSUER = "https://auth.${vars.domain}";
          OC_OIDC_CLIENT_ID = "opencloud";
          WEB_OIDC_CLIENT_ID = "opencloud";
          WEB_OIDC_SCOPE = "openid profile email groups";
          PROXY_OIDC_REWRITE_WELLKNOWN = "true";
          PROXY_AUTOPROVISION_ACCOUNTS = "true";

          IDP_DOMAIN = "auth.${vars.domain}";
        };
        settings = {
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
    };
  };

  # Define custom middleware for Traefik on the host
  services.traefik.dynamicConfigOptions.http.middlewares.opencloud-headers = {
    headers = {
      sslRedirect = true;
      frameDeny = true;
      contentTypeNosniff = true;
      browserXssFilter = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/opencloud 0750 root root -"
  ];
}
