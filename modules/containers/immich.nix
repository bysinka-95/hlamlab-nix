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

    # Machine-learning models are downloaded on first use.
    internet = true;

    secrets = {
      immich-oidc-client-secret = {
        key = "immich/oidc-client-secret";
      };
    };

    containerConfig = { pkgs, ... }: {
      # Pinned to the major version the existing cluster was initdb'd with.
      # NixOS derives this default from system.stateVersion, so leaving it out
      # would silently step 16 -> 17 and postgres would refuse to start on the
      # old PGDATA. Bumping it means a manual pg_upgrade first.
      services.postgresql.package = pkgs.postgresql_16;

      services.immich = {
        enable = true;
        host = "0.0.0.0";
        port = svc.immich.port;
        # No "create the admin" onboarding page: admins come from OIDC.
        environment.IMMICH_ALLOW_SETUP = "false";

        settings = {
          server.externalDomain = svc.immich.baseUrl;
          passwordLogin.enabled = false;

          oauth = {
            enabled = true;
            issuerUrl = svc.authelia.baseUrl;
            clientId = "immich";
            clientSecret._secret = svc.immich.secrets.immich-oidc-client-secret.path;
            # `immich_role` carries the admin flag (see authelia.nix).
            scope = "openid email profile immich_role";
            autoRegister = true;
            # Straight to Authelia; the button page stays at
            # /auth/login?autoLaunch=0.
            autoLaunch = true;
            buttonText = "Login with Authelia";
            tokenEndpointAuthMethod = "client_secret_post";
          };
        };
      };
    };
  };

}
