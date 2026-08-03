{ lib, config, ... }:
let
  hostConfig = config;
  svc = hostConfig.hlamlab.services;
in
{
  hlamlab.services.immich = {
    ip = lib.mkDefault "10.0.0.3";
    port = lib.mkDefault 2283;
    domainPrefix = lib.mkDefault "immich";
    storageQuota = lib.mkDefault "300G";
    storageReservation = lib.mkDefault "10G";

    cpuLimit = lib.mkDefault "200%";
    ramLimit = lib.mkDefault "4G";
    ramHigh = lib.mkDefault "3G";

    nameservers = [ "1.1.1.1" "1.0.0.1" ];

    bindMounts = {
      "/var/lib/immich" = {
        hostPath = "/var/lib/services/immich";
        isReadOnly = false;
      };
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
        port = svc.immich.port;
        mediaLocation = "/var/lib/immich";

        settings = {
          server.externalDomain = svc.immich.baseUrl;
          passwordLogin.enabled = false;

          oauth = {
            enabled = true;
            issuerUrl = svc.authelia.baseUrl;
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

}
