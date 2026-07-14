{ config, ... }:
let
  vars = import ../../common/settings.nix;
in
{
  hlamlab.services.immich = {
    ip = "10.0.0.3";
    port = 2283;
    domainPrefix = "immich";
    storageQuota = "300G";
    storageReservation = "10G";
    
    bindMounts = {
      "/var/lib/immich" = {
        hostPath = "/var/lib/services/immich";
        isReadOnly = false;
      };
    };

    resourceLimits = {
      CPUQuota = "200%";
      CPUWeight = 200;
      MemoryMax = "4G";
      MemoryHigh = "3G";
      MemorySwapMax = "0B";
      IOWeight = 200;
      TasksMax = 1024;
    };

    secrets = {
      immich-oidc-client-secret = {
        key = "immich/oidc-client-secret";
        restartUnits = [ "immich-server.service" "immich-microservices.service" ];
      };
    };

    containerConfig = { pkgs, config, ... }: {
      services.immich = {
        enable = true;
        package = pkgs.immich;
        host = "0.0.0.0";
        port = 2283;
        mediaLocation = "/var/lib/immich";

        settings = {
          server.externalDomain = "https://immich.${vars.domain}";
          passwordLogin.enabled = false;

          oauth = {
            enabled = true;
            issuerUrl = "https://auth.${vars.domain}";
            clientId = "immich";
            clientSecret._secret = config.sops.secrets.immich-oidc-client-secret.path;
            scope = "openid email profile";
            autoRegister = true;
            autoLaunch = false;
            buttonText = "Login with Authelia";
            tokenEndpointAuthMethod = "client_secret_post";
          };
        };

        database = {
          enable = true;
          createDB = true;
          host = "/run/postgresql";
          name = "immich";
          user = "immich";
        };

        redis = {
          enable = true;
          host = "127.0.0.1";
          port = 6379;
        };

        machine-learning.enable = true;
      };

      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_16;
      };

      services.redis.servers."".enable = true;

      systemd.services.immich-server.serviceConfig.StateDirectory = "immich";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/immich 0755 root root -"
  ];
}
