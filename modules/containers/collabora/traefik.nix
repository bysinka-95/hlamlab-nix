{ ... }:
let
  vars = import ../../common/settings.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
      middlewares = {
        collabora-headers = {
          headers = {
            sslRedirect = true;
            frameDeny = false;
            customFrameOptionsValue = "ALLOW-FROM https://opencloud.${vars.domain}";
            contentSecurityPolicy = "frame-ancestors 'self' https://opencloud.${vars.domain}";
            contentTypeNosniff = true;
            browserXssFilter = true;
          };
        };
      };

      routers.collabora = {
        rule = "Host(`collabora.${vars.domain}`)";
        service = "collabora";
        entryPoints = [ "https" ];
        tls = { };
        middlewares = [ "collabora-headers" ];
      };

      services.collabora = {
        loadBalancer = {
          servers = [{ url = "http://collabora:9980"; }];
          passHostHeader = true;
        };
      };
    };
  };
}

