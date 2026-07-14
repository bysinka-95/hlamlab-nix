{ lib, ... }:
let
  vars = import ../../common/settings.nix;
in
{
  hlamlab.services.collabora = {
    ip = lib.mkDefault "10.0.0.4";
    port = lib.mkDefault 9980;
    domainPrefix = lib.mkDefault "collabora";
    storageQuota = lib.mkDefault "20G";
    storageReservation = lib.mkDefault "5G";

    cpuLimit = lib.mkDefault "100%";
    ramLimit = lib.mkDefault "1.5G";
    ramHigh = lib.mkDefault "1G";

    bindMounts = {
      "/var/lib/coolwsd" = {
        hostPath = "/var/lib/services/collabora";
        isReadOnly = false;
      };
    };

    traefikMiddlewares = [ "collabora-headers" ];

    containerConfig = { ... }: {
      services.collabora-online = {
        enable = true;
        port = 9980;

        settings = {
          ssl = {
            enable = false;
            termination = true;
          };

          storage.wopi = {
            "@allow" = true;
            host = [ "opencloud.${vars.domain}" ];
          };

          server_name = "collabora.${vars.domain}";
        };
      };
    };
  };

  services.traefik.dynamicConfigOptions.http.middlewares.collabora-headers = {
    headers = {
      sslRedirect = true;
      frameDeny = false;
      customFrameOptionsValue = "ALLOW-FROM https://opencloud.${vars.domain}";
      contentSecurityPolicy = "frame-ancestors 'self' https://opencloud.${vars.domain}";
      contentTypeNosniff = true;
      browserXssFilter = true;
    };
  };
}
