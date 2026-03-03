{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  # Native NixOS container running Immich
  containers.immich = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1"; # host side of the veth
    localAddress = "10.0.0.3"; # container IP

    # Bind mount: Host storage → Container storage
    # This makes photos/videos survive container recreation
    bindMounts = {
      "/var/lib/immich" = {
        hostPath = "/var/lib/services/immich";
        isReadOnly = false;
      };
    };

    config = { pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 2283 ]; # Immich default port

      # Immich service with full stack (app + DB + Redis + ML)
      services.immich = {
        enable = true;
        package = pkgs.immich;
        host = "0.0.0.0"; # Listen on all interfaces (required for host access)
        port = 2283;

        # Media storage location (inside container)
        mediaLocation = "/var/lib/immich";

        # External domain for publicly shared links
        settings.server.externalDomain = "https://immich.${vars.domain}";

        # Integrated PostgreSQL database
        database = {
          enable = true;
          createDB = true;
          enableVectors = true; # pgvecto.rs for similarity search
          enableVectorChord = true; # New full-text search extension
          host = "/run/postgresql"; # Unix socket
          name = "immich";
          user = "immich";
        };

        # Integrated Redis cache
        redis = {
          enable = true;
          host = "127.0.0.1";
          port = 6379;
        };

        # Machine learning for face detection & object search
        machine-learning.enable = true;
      };

      # Enable PostgreSQL service (required by Immich)
      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_16;
      };

      # Enable Redis service (required by Immich)
      services.redis.servers."".enable = true;

      system.stateVersion = "26.05";
    };
  };

  # Create the host directory for Immich media storage
  # This directory will be bind-mounted into the container
  # Ownership will be managed by the container's immich user automatically
  systemd.tmpfiles.rules = [
    "d /var/lib/services 0755 root root -"
    "d /var/lib/services/immich 0755 root root -"
  ];
}


