{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  # Traefik configuration for Immich
  services.traefik.dynamicConfigOptions = {
    http = {
      # Router: immich.yourdomain → immich container
      routers.immich = {
        rule = "Host(`immich.${vars.domain}`)";
        service = "immich";
        entryPoints = [ "https" ];
        tls = { };
        middlewares = [ "security-headers" ];
      };

      # Service: Backend configuration
      services.immich = {
        loadBalancer = {
          servers = [{ url = "http://immich:2283"; }]; # DNS name from default.nix
          passHostHeader = true;
        };
      };
    };
  };
}

