{ config, inputs, ... }:
let
  vars = import ../../common/settings.nix;
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
      "/var/lib/sops-nix/key.txt" = {
        hostPath = "/var/lib/sops-nix/key.txt";
        isReadOnly = true;
      };
    };

    config = { pkgs, config, ... }: {
      imports = [
        inputs.sops-nix.nixosModules.sops
      ];

      sops = {
        defaultSopsFile = ../../secrets/secrets.yaml;
        defaultSopsFormat = "yaml";
        age.keyFile = "/var/lib/sops-nix/key.txt";

        secrets = {
          immich-oidc-client-secret = {
            key = "immich/oidc-client-secret";
            owner = "immich";
            group = "immich";
            mode = "0400";
            restartUnits = [ "immich-server.service" "immich-microservices.service" ];
          };
        };
      };

      networking.firewall.allowedTCPPorts = [ 2283 ]; # Immich default port
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
            clientSecret._secret = config.sops.secrets.immich-oidc-client-secret.path;
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

      # Dynamic user/group
      users.users.immich = {
        isSystemUser = true;
        group = "immich";
        description = "Immich service user";
      };
      users.groups.immich = { };

      systemd.services.immich-server.serviceConfig.StateDirectory = "immich";

      system.stateVersion = "26.05";
    };
  };

  # Create the host directory for Immich media storage
  systemd.tmpfiles.rules = [
    "d /var/lib/services 0755 root root -"
    "d /var/lib/services/immich 0755 root root -"
  ];
}


