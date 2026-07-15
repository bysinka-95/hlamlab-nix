{ lib, config, ... }:
let
  hostConfig = config;
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

    nameservers = [ "1.1.1.1" "1.0.0.1" ];

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
            host = [ "opencloud.${hostConfig.hlamlab.settings.domain}" ];
          };

          server_name = "collabora.${hostConfig.hlamlab.settings.domain}";
        };
      };
    };
  };

  services.traefik.dynamicConfigOptions.http.middlewares.collabora-headers = {
    headers = {
      sslRedirect = true;
      frameDeny = false;
      customFrameOptionsValue = "ALLOW-FROM https://opencloud.${hostConfig.hlamlab.settings.domain}";
      contentSecurityPolicy = "frame-ancestors 'self' https://opencloud.${hostConfig.hlamlab.settings.domain}";
      contentTypeNosniff = true;
      browserXssFilter = true;
    };
  };
}
