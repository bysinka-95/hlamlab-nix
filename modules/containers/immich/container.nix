{ config, ... }:
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
      "/run/secrets/immich-oidc-client-secret" = {
        hostPath = config.sops.secrets.immich-immich-oidc-client-secret.path;
        isReadOnly = true;
      };
    };

    config = { pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 2283 ]; # Immich default port

      users.users.immich.uid = 902;
      users.groups.immich.gid = 902;

      # Systemd-resolved running on the host (127.0.0.53) is unreachable from
      # inside the isolated container network, causing DNS resolution to fail.
      # Hardcoding public nameservers allows the container to resolve domains
      # and reach external services or identity providers.
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

      # Immich service with full stack (app + DB + Redis + ML)
      services.immich = {
        enable = true;
        package = pkgs.immich;
        host = "0.0.0.0"; # Listen on all interfaces (required for host access)
        port = 2283;

        # Media storage location (inside container)
        mediaLocation = "/var/lib/immich";

        # External domain for publicly shared links
        settings = {
          server.externalDomain = "https://immich.${vars.domain}";

          passwordLogin.enabled = false;

          # Native OIDC login via Authelia.
          oauth = {
            enabled = true;
            issuerUrl = "https://auth.${vars.domain}";
            clientId = "immich";
            clientSecret._secret = "/run/secrets/immich-oidc-client-secret";
            scope = "openid email profile";
            autoRegister = true;
            autoLaunch = false;
            buttonText = "Login with Authelia";

            # Authelia supports PKCE and standard auth methods
            tokenEndpointAuthMethod = "client_secret_post";
          };
        };

        # Integrated PostgreSQL database
        database = {
          enable = true;
          createDB = true;
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


