{ ... }:
let
  vars = import ../../common/settings.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
      routers.lldap = {
        rule = "Host(`lldap.${vars.domain}`)";
        service = "lldap";
        entryPoints = [ "https" ];
        tls = { };
        middlewares = [ "security-headers" ];
      };

      services.lldap = {
        loadBalancer = {
          servers = [{ url = "http://lldap:3000"; }];
          passHostHeader = true;
        };
      };
    };
  };
}