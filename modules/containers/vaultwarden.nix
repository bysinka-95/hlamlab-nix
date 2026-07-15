{ lib, config, ... }:
let
  hostConfig = config;
in
{
  hlamlab.services.vaultwarden = {
    ip = lib.mkDefault "10.0.0.7";
    port = lib.mkDefault 8222;
    domainPrefix = lib.mkDefault "vault";
    storageQuota = lib.mkDefault "10G";
    storageReservation = lib.mkDefault "1G";

    cpuLimit = lib.mkDefault "100%";
    ramLimit = lib.mkDefault "1G";
    ramHigh = lib.mkDefault "512M";

    nameservers = [ "1.1.1.1" "1.0.0.1" ];

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
          DOMAIN = "https://vault.${hostConfig.hlamlab.settings.domain}";

          SIGNUPS_ALLOWED = false;

          DATA_FOLDER = "/var/lib/vaultwarden";

          SSO_ENABLED = true;
          SSO_ONLY = true;
          SSO_AUTHORITY = "https://auth.${hostConfig.hlamlab.settings.domain}";
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
    "d /var/lib/services/vaultwarden 0750 - - -"
  ];
}
