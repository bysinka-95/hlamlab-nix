{ ... }:
let
  vars = import ../../common/settings.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
      routers.immich = {
        rule = "Host(`immich.${vars.domain}`)";
        service = "immich";
        entryPoints = [ "https" ];
        tls = { };
        middlewares = [ "security-headers" ];
      };

      services.immich = {
        loadBalancer = {
          servers = [{ url = "http://immich:2283"; }];
          passHostHeader = true;
        };
      };
    };
  };
}

