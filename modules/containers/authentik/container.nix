{ config, inputs, ... }:
{
  containers.authentik = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.5";

    bindMounts = {
      # PostgreSQL data directory bind mount (for persistence)
      "/var/lib/postgresql" = {
        hostPath = "/var/lib/services/authentik/postgresql";
        isReadOnly = false;
      };
      # Redis data directory bind mount (for persistence)
      "/var/lib/redis" = {
        hostPath = "/var/lib/services/authentik/redis";
        isReadOnly = false;
      };
      "/run/secrets/authentik-env" = {
        hostPath = config.sops.secrets.authentik-env.path;
        isReadOnly = true;
      };
    };

    config = { pkgs, ... }: {
      imports = [
        inputs.authentik-nix.nixosModules.default
      ];

      # Authentik uses 9000 for web interface and 9443 for HTTPS
      networking.firewall.allowedTCPPorts = [ 9000 9443 ];

      # Systemd-resolved running on the host (127.0.0.53) is unreachable from
      # inside the isolated container network, causing DNS resolution to fail.
      # Hardcoding public nameservers allows the container to resolve domains
      # and reach external services (like version.goauthentik.io).
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

      # Authentik configuration
      services.authentik = {
        enable = true;
        environmentFile = "/run/secrets/authentik-env";

        # We define settings for local database and redis within the container
        settings = {
          email = {
            # email settings can be added here or in environmentFile
          };
          disable_startup_analytics = true;
          avatars = "initials";
        };
      };

      # Integrated PostgreSQL database within the container
      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_16;
        dataDir = "/var/lib/postgresql/16"; # Match the version
      };

      # Integrated Redis server within the container
      services.redis.servers."".enable = true;

      system.stateVersion = "26.05";
    };
  };

  # Create host directories for persistent storage, but intentionally
  # leave /var/lib/authentik unmounted so systemd's DynamicUser won't break.
  systemd.tmpfiles.rules = [
    "d /var/lib/services/authentik 0755 root root -"
    "d /var/lib/services/authentik/postgresql 0750 71 71 -" # UID/GID 71 is postgres in NixOS
    "d /var/lib/services/authentik/redis 0750 999 999 -"    # Placeholder UID for redis
  ];
}
