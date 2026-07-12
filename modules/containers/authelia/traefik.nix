{ ... }:
let
  vars = import ../../common/settings.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
      routers.authelia = {
        rule = "Host(`auth.${vars.domain}`)";
        service = "authelia";
        entryPoints = [ "https" ];
        tls = { };
        middlewares = [ "security-headers" ];
      };

      services.authelia = {
        loadBalancer = {
          servers = [{ url = "http://authelia:9091"; }];
          passHostHeader = true;
        };
      };
    };
  };
}

