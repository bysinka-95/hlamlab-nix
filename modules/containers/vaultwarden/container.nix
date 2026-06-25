{ config, lib, ... }:
let
  vars = import ../../common/local.nix;
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
      "/run/secrets/vaultwarden-env" = {
        hostPath = config.sops.secrets.vaultwarden-env.path;
        isReadOnly = true;
      };
    };

    config = { lib, pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 8222 ];
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

      services.vaultwarden = {
        enable = true;

        # ADMIN_TOKEN and SSO_CLIENT_SECRET are injected from the env file.
        # The env file must contain:
        #   ADMIN_TOKEN=<your-token>
        #   SSO_CLIENT_SECRET=<shared-secret-matching-authelia-client>
        environmentFile = "/run/secrets/vaultwarden-env";

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
        StateDirectory = lib.mkForce "";
        User = "vaultwarden";
        Group = "vaultwarden";
      };

      # Static UID/GID to match host-side tmpfiles ownership
      users.users.vaultwarden = {
        isSystemUser = true;
        group = "vaultwarden";
        uid = 904;
      };
      users.groups.vaultwarden = {
        gid = 904;
      };

      system.stateVersion = "26.05";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/vaultwarden 0750 904 904 -"
  ];
}
