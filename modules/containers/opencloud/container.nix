{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  # Native NixOS container running OpenCloud
  containers.opencloud = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1"; # host side of the veth
    localAddress = "10.0.0.2"; # container IP

    # Bind mount: Host storage → Container storage
    # This makes OpenCloud state persist across container recreation
    bindMounts = {
      "/var/lib/opencloud" = {
        hostPath = "/var/lib/services/opencloud";
        isReadOnly = false;
      };
    };

    config = { pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 9200 9300 ];

      # Systemd-resolved running on the host (127.0.0.53) is unreachable from
      # inside the isolated container network, causing DNS resolution to fail.
      # Hardcoding public nameservers allows the container to resolve its own
      # Cloudflare-proxied domain name correctly and route through the tunnel.
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

      services.opencloud = {
        enable = true;
        url = "https://opencloud.${vars.domain}"; # Public URL for proper operation behind Traefik
        address = "0.0.0.0";
        port = 9200;
        environment = {
          PROXY_TLS = "false";
          INITIAL_ADMIN_PASSWORD = "admin"; # Set initial admin password (change after first login)

          OC_ADD_RUN_SERVICES = "collaboration";

          # Native OIDC integration with Kanidm.
          OC_OIDC_ISSUER = "https://auth.${vars.domain}/oauth2/openid/opencloud";
          OC_OIDC_CLIENT_ID = "opencloud";
          WEB_OIDC_CLIENT_ID = "opencloud";
          WEB_OIDC_SCOPE = "openid profile email groups";
          PROXY_OIDC_REWRITE_WELLKNOWN = "true";
          PROXY_AUTOPROVISION_ACCOUNTS = "true";

          # Keeps OpenCloud CSP IDP placeholders aligned with Kanidm.
          IDP_DOMAIN = "auth.${vars.domain}";
        };
        settings = {
          collaboration = {
            app = {
              name = "Office";
              product = "Collabora";
              addr = "https://collabora.${vars.domain}";
              insecure = false;
            };
            wopi = {
              src = "https://opencloud.${vars.domain}";
            };
          };
          csp = {
            directives = {
              child-src = [ "'self'" ];
              connect-src = [
                "'self'"
                "blob:"
                "https://\${COMPANION_DOMAIN|companion.opencloud.test}\${TRAEFIK_PORT_HTTPS}/"
                "wss://\${COMPANION_DOMAIN|companion.opencloud.test}\${TRAEFIK_PORT_HTTPS}/"
                "https://raw.githubusercontent.com/opencloud-eu/awesome-apps/"
                "https://\${IDP_DOMAIN|keycloak.opencloud.test}\${TRAEFIK_PORT_HTTPS}/"
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
                "https://\${IDP_DOMAIN|keycloak.opencloud.test}\${TRAEFIK_PORT_HTTPS}/"
              ];
              style-src = [ "'self'" "'unsafe-inline'" ];
            };
          };

          proxy.csp_config_file_location = "/etc/opencloud/csp.yaml";
        };
      };


      system.stateVersion = "25.11";
    };
  };

  # Create the host directory for OpenCloud state storage
  # This directory will be bind-mounted into the container
  # Ownership will be managed by the container's opencloud user automatically
  systemd.tmpfiles.rules = [
    "d /var/lib/services 0755 root root -"
    "d /var/lib/services/opencloud 0755 root root -"
  ];
}
