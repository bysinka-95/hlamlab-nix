{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  # Traefik configuration for OpenCloud service
  services.traefik.dynamicConfigOptions = {
    http = {
      # OpenCloud-specific middleware
      middlewares = {
        security-headers-opencloud = {
          headers = {
            sslRedirect = true;
            frameDeny = true;
            contentTypeNosniff = true;
            browserXssFilter = true;
          };
        };
      };

      # OpenCloud router
      routers = {
        opencloud = {
          rule = "Host(`opencloud.${vars.domain}`)";
          entryPoints = [ "https" ];
          service = "opencloud";
          tls = {};
          middlewares = [ "security-headers-opencloud" ];
        };
      };

      # OpenCloud backend service
      services = {
        opencloud = {
          loadBalancer = {
            servers = [
              { url = "https://opencloud:9200"; }
            ];
            passHostHeader = true;
          };
        };
      };
    };
  };
}

