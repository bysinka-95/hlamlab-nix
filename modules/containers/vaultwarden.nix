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
        restartUnits = [ "vaultwarden.service" ];
      };
    };

    containerConfig = { config, ... }: {
      services.vaultwarden = {
        enable = true;
        environmentFile = config.sops.secrets.vaultwarden-env.path;

        config = {
          ROCKET_ADDRESS = "0.0.0.0";
          ROCKET_PORT = svc.vaultwarden.port;
          DOMAIN = svc.vaultwarden.baseUrl;

          SIGNUPS_ALLOWED = false;

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

}
