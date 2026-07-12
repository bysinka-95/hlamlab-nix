{ ... }:
let
  vars = import ../../common/settings.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
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

      routers.opencloud = {
        rule = "Host(`opencloud.${vars.domain}`)";
        entryPoints = [ "https" ];
        service = "opencloud";
        tls = { };
        middlewares = [ "opencloud-headers" ];
      };

      services.opencloud = {
        loadBalancer = {
          servers = [{ url = "http://opencloud:9200"; }];
          passHostHeader = true;
        };
      };
    };
  };
}
