{ ... }:
let
  vars = import ../../common/settings.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
      routers.searx = {
        rule = "Host(`searxng.${vars.domain}`)";
        service = "searx";
        entryPoints = [ "https" ];
        tls = { };
        middlewares = [ "security-headers" ];
      };

      services.searx = {
        loadBalancer = {
          servers = [{ url = "http://searx:8888"; }];
          passHostHeader = true;
        };
      };
    };
  };
}
