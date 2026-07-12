{ ... }:
let
  vars = import ../../common/settings.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
      routers.vaultwarden = {
        rule = "Host(`vault.${vars.domain}`)";
        service = "vaultwarden";
        entryPoints = [ "https" ];
        tls = { };
        middlewares = [ "security-headers" ];
      };

      services.vaultwarden = {
        loadBalancer = {
          servers = [{ url = "http://vaultwarden:8222"; }];
          passHostHeader = true;
        };
      };
    };
  };
}
