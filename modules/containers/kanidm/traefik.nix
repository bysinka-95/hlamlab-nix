{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
      routers.kanidm = {
        rule = "Host(`auth.${vars.domain}`)";
        service = "kanidm";
        entryPoints = [ "https" ];
        tls = { };
        middlewares = [ "security-headers" ];
      };

      services.kanidm = {
        loadBalancer = {
          servers = [{ url = "https://kanidm:8443"; }];
          passHostHeader = true;
        };
      };
    };
  };
}
