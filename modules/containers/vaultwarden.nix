{ config, ... }:
let
  svc = config.hlamlab.services;
in
{
  hlamlab.services.vaultwarden = {
    ip = "10.0.0.7";
    port = 8222;
    domainPrefix = "vault";

    secrets = {
      vaultwarden-env = {
        key = "vaultwarden/env";
      };
    };

    containerConfig = { ... }: {
      services.vaultwarden = {
        enable = true;
        environmentFile = svc.vaultwarden.secrets.vaultwarden-env.path;

        config = {
          ROCKET_ADDRESS = "0.0.0.0";
          ROCKET_PORT = svc.vaultwarden.port;
          DOMAIN = svc.vaultwarden.baseUrl;

          SIGNUPS_ALLOWED = false;

          # No internet egress: the client fetches site icons itself (by
          # redirect) instead of the server downloading them.
          ICON_SERVICE = "duckduckgo";

          DATA_FOLDER = "/var/lib/vaultwarden";

          SSO_ENABLED = true;
          SSO_ONLY = true;
          SSO_AUTHORITY = svc.authelia.baseUrl;
          SSO_CLIENT_ID = "vaultwarden";
          SSO_CLIENT_CACHE_EXPIRATION = 600;
          SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION = true;
          SSO_SIGNUPS_MATCH_EMAIL = true;
        };
      };

      systemd.services.vaultwarden.serviceConfig.ReadWritePaths = [ "/var/lib/vaultwarden" ];
    };
  };

  # /admin goes through Authelia's gate; ADMIN_TOKEN stays as the second lock.
  # Traefik prefers the longer rule, so everything else keeps the frame's
  # router, and the apps' API paths stay ungated.
  services.traefik.dynamicConfigOptions.http.routers.vaultwarden-admin = {
    rule = "Host(`${svc.vaultwarden.fqdn}`) && PathPrefix(`/admin`)";
    service = "vaultwarden";
    entryPoints = [ "https" ];
    middlewares = [ "authelia" "security-headers" ];
  };
}
