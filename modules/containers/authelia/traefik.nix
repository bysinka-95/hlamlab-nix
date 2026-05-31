{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  # Traefik configuration for Authelia
  services.traefik.dynamicConfigOptions = {
    http = {
      # Router: auth.yourdomain → authelia container
      routers.authelia = {
        rule = "Host(`auth.${vars.domain}`)";
        service = "authelia";
        entryPoints = [ "https" ];
        tls = { };
        middlewares = [ "security-headers" ];
      };

      # Service: Backend configuration
      services.authelia = {
        loadBalancer = {
          servers = [{ url = "http://authelia:9091"; }]; # DNS name from default.nix
          passHostHeader = true;
        };
      };
    };
  };
}

