{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
      middlewares = {
        authentik-headers = {
          forwardAuth = {
            address = "https://authentik:9443/outpost.goauthentik.io/auth/traefik";
            trustForwardHeader = true;
            authResponseHeaders = [
              "X-authentik-username"
              "X-authentik-groups"
              "X-authentik-email"
              "X-authentik-name"
              "X-authentik-uid"
              "X-authentik-jwt"
              "X-authentik-meta-jwks"
              "X-authentik-meta-outpost"
              "X-authentik-meta-provider"
              "X-authentik-meta-app"
              "X-authentik-meta-version"
            ];
          };
        };
      };

      routers.authentik = {
        # Route requests to the authentik portal OR to the outpost authentication endpoints on any subdomain
        rule = "Host(`auth.${vars.domain}`) || (HostRegexp(`{subdomain:[a-z0-9]+}.${vars.domain}`) && PathPrefix(`/outpost.goauthentik.io/`))";
        service = "authentik";
        entryPoints = [ "https" ];
        tls = { };
        middlewares = [ "security-headers" ];
      };

      services.authentik = {
        loadBalancer = {
          servers = [{ url = "http://authentik:9000"; }];
          passHostHeader = true;
        };
      };
    };
  };
}
