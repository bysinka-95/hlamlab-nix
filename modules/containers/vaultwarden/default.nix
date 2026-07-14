{ ... }:
let
  vars = import ../../common/settings.nix;
in
{
  hlamlab.services.vaultwarden = {
    ip = "10.0.0.7";
    port = 8222;
    domainPrefix = "vault";
    storageQuota = "10G";
    storageReservation = "1G";
    
    bindMounts = {
      "/var/lib/vaultwarden" = {
        hostPath = "/var/lib/services/vaultwarden";
        isReadOnly = false;
      };
    };

    secrets = {
      vaultwarden-env = {
        key = "vaultwarden/env";
        restartUnits = [ "vaultwarden.service" ];
      };
    };

    containerConfig = { lib, pkgs, config, ... }: {
      services.vaultwarden = {
        enable = true;
        environmentFile = config.sops.secrets.vaultwarden-env.path;

        config = {
          ROCKET_ADDRESS = "0.0.0.0";
          ROCKET_PORT = 8222;
          DOMAIN = "https://vault.${vars.domain}";

          SIGNUPS_ALLOWED = false;

          DATA_FOLDER = "/var/lib/vaultwarden";

          SSO_ENABLED = true;
          SSO_ONLY = true;
          SSO_AUTHORITY = "https://auth.${vars.domain}";
          SSO_CLIENT_ID = "vaultwarden";
          SSO_CLIENT_CACHE_EXPIRATION = 600;
          SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION = true;
          SSO_SIGNUPS_MATCH_EMAIL = true;
        };
      };

      systemd.services.vaultwarden.serviceConfig = {
        ReadWritePaths = [ "/var/lib/vaultwarden" ];
        StateDirectory = "vaultwarden";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/vaultwarden 0750 root root -"
  ];
}
