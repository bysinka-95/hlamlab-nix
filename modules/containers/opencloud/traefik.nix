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
        opencloud-headers = {
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
          tls = { };
          middlewares = [ "opencloud-headers" ];
        };
      };

      # OpenCloud backend service
      services = {
        opencloud = {
          loadBalancer = {
            servers = [
              { url = "http://opencloud:9200"; }
            ];
            passHostHeader = true;
          };
        };
      };
    };
  };
}

