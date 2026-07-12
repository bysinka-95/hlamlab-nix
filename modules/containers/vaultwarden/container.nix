{ config, inputs, ... }:
let
  vars = import ../../common/settings.nix;
in
{
  containers.vaultwarden = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.7";

    bindMounts = {
      "/var/lib/vaultwarden" = {
        hostPath = "/var/lib/services/vaultwarden";
        isReadOnly = false;
      };
      "/var/lib/sops-nix/key.txt" = {
        hostPath = "/var/lib/sops-nix/key.txt";
        isReadOnly = true;
      };
    };

    config = { lib, pkgs, config, ... }: {
      imports = [
        inputs.sops-nix.nixosModules.sops
      ];

      sops = {
        defaultSopsFile = ../../secrets/secrets.yaml;
        defaultSopsFormat = "yaml";
        age.keyFile = "/var/lib/sops-nix/key.txt";

        secrets = {
          vaultwarden-env = {
            key = "vaultwarden/env";
            owner = "vaultwarden";
            group = "vaultwarden";
            mode = "0400";
            restartUnits = [ "vaultwarden.service" ];
          };
        };
      };

      networking.firewall.allowedTCPPorts = [ 8222 ];
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

      services.vaultwarden = {
        enable = true;
        environmentFile = config.sops.secrets.vaultwarden-env.path;

        config = {
          ROCKET_ADDRESS = "0.0.0.0";
          ROCKET_PORT = 8222;
          DOMAIN = "https://vault.${vars.domain}";

          # Disable local signups and password auth — SSO only
          SIGNUPS_ALLOWED = false;

          DATA_FOLDER = "/var/lib/vaultwarden";

          # Authelia SSO (OpenID Connect)
          SSO_ENABLED = true;
          SSO_ONLY = true;
          SSO_AUTHORITY = "https://auth.${vars.domain}";
          SSO_CLIENT_ID = "vaultwarden";
          # Cache the discovery endpoint for 10 minutes
          SSO_CLIENT_CACHE_EXPIRATION = 600;
          # Authelia doesn't always emit email_verified; allow unknown status
          SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION = true;
          # Associate existing accounts by email on first SSO login
          SSO_SIGNUPS_MATCH_EMAIL = true;
        };
      };

      # Ensure vaultwarden has write access to its data directory
      systemd.services.vaultwarden.serviceConfig = {
        ReadWritePaths = [ "/var/lib/vaultwarden" ];
        DynamicUser = lib.mkForce false;
        StateDirectory = "vaultwarden";
        User = "vaultwarden";
        Group = "vaultwarden";
      };

      # Dynamic user/group
      users.users.vaultwarden = {
        isSystemUser = true;
        group = "vaultwarden";
        description = "Vaultwarden service user";
      };
      users.groups.vaultwarden = { };

      system.stateVersion = "26.05";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/vaultwarden 0750 root root -"
  ];
}
