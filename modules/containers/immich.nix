{ config, ... }:
let
  svc = config.hlamlab.services;
in
{
  hlamlab.services.immich = {
    ip = "10.0.0.3";
    port = 2283;
    storageQuota = "300G";
    storageReservation = "10G";

    cpuLimit = "200%";
    ramLimit = "4G";
    ramHigh = "3G";

    secrets = {
      immich-oidc-client-secret = {
        key = "immich/oidc-client-secret";
        restartUnits = [ "immich-server.service" "immich-microservices.service" ];
      };
    };

    containerConfig = { config, pkgs, ... }: {
      # Pinned to the major version the existing cluster was initdb'd with.
      # NixOS derives this default from system.stateVersion, so leaving it out
      # would silently step 16 -> 17 and postgres would refuse to start on the
      # old PGDATA. Bumping it means a manual pg_upgrade first.
      services.postgresql.package = pkgs.postgresql_16;

      services.immich = {
        enable = true;
        host = "0.0.0.0";
        port = svc.immich.port;

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
      };
    };
  };

}
