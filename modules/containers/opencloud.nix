{ config, ... }:
let
  svc = config.hlamlab.services;
in
{
  hlamlab.services.opencloud = {
    ip = "10.0.0.2";
    port = 9200;
    storageQuota = "50G";
    storageReservation = "10G";

    ramLimit = "2G";
    ramHigh = "1.5G";

    secrets = {
      opencloud-sharing-secret = {
        key = "opencloud/sharing-secret";
      };
    };

    containerConfig = { pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 9300 ];

      services.opencloud = {
        enable = true;
        # The module has no default since nixpkgs split rolling and production
        # releases. Rolling is what ran before, and OpenCloud cannot downgrade.
        package = pkgs.opencloud;
        url = svc.opencloud.baseUrl;
        address = "0.0.0.0";
        port = svc.opencloud.port;
        environmentFile = svc.opencloud.secrets.opencloud-sharing-secret.path;
        environment = {
          PROXY_TLS = "false";
          INITIAL_ADMIN_PASSWORD = "admin";

          OC_ADD_RUN_SERVICES = "collaboration";

          COLLABORATION_APP_NAME = "Office";
          COLLABORATION_APP_PRODUCT = "Collabora";
          COLLABORATION_APP_ADDR = svc.collabora.baseUrl;
          COLLABORATION_APP_INSECURE = "false";
          COLLABORATION_WOPI_SRC = svc.opencloud.baseUrl;
          COLLABORATION_APP_PROOF_DISABLE = "true";

          OC_OIDC_ISSUER = svc.authelia.baseUrl;
          OC_OIDC_CLIENT_ID = "opencloud";
          WEB_OIDC_CLIENT_ID = "opencloud";
          WEB_OIDC_SCOPE = "openid profile email groups opencloud_role";
          PROXY_OIDC_REWRITE_WELLKNOWN = "true";
          PROXY_AUTOPROVISION_ACCOUNTS = "true";
          # Role from the `opencloud_role` claim (see authelia.nix), re-applied on
          # every login. Uses OpenCloud's default mapping: opencloudAdmin → admin,
          # opencloudUser → user; a login without a mapped value is refused.
          PROXY_ROLE_ASSIGNMENT_DRIVER = "oidc";
          PROXY_ROLE_ASSIGNMENT_OIDC_CLAIM = "opencloud_role";

          IDP_DOMAIN = svc.authelia.fqdn;
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
                "https://\${IDP_DOMAIN|${svc.authelia.fqdn}}\${TRAEFIK_PORT_HTTPS}/"
                "https://update.opencloud.eu/"
              ];
              default-src = [ "'none'" ];
              font-src = [ "'self'" ];
              frame-ancestors = [ "'self'" ];
              frame-src = [
                "'self'"
                "blob:"
                "https://embed.diagrams.net/"
                svc.collabora.baseUrl
                "https://docs.opencloud.eu"
                # OIDC silent renew loads the IdP's authorize endpoint in a
                # hidden iframe. Without this, default-src 'none' blocks it, the
                # iframe never posts back, and oidc-client waits out its timeout
                # four times (~1 min) before falling back to interactive login.
                svc.authelia.baseUrl
              ];
              img-src = [
                "'self'"
                "data:"
                "blob:"
                "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                "https://tile.openstreetmap.org/"
                "${svc.collabora.baseUrl}/"
              ];
              manifest-src = [ "'self'" ];
              media-src = [ "'self'" ];
              object-src = [ "'self'" "blob:" ];
              script-src = [
                "'self'"
                "'unsafe-inline'"
                "https://\${IDP_DOMAIN|${svc.authelia.fqdn}}\${TRAEFIK_PORT_HTTPS}/"
              ];
              style-src = [ "'self'" "'unsafe-inline'" ];
            };
          };

          proxy.csp_config_file_location = "/etc/opencloud/csp.yaml";
        };
      };

    };
  };
}
