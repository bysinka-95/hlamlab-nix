{ ... }:
let
  vars = import ../../common/settings.nix;
in
{
  hlamlab.services.collabora = {
    ip = "10.0.0.4";
    port = 9980;
    domainPrefix = "collabora";
    storageQuota = "20G";
    storageReservation = "5G";
    
    bindMounts = {
      "/var/lib/coolwsd" = {
        hostPath = "/var/lib/services/collabora";
        isReadOnly = false;
      };
    };

    traefikMiddlewares = [ "collabora-headers" ];

    resourceLimits = {
      CPUQuota = "100%";
      CPUWeight = 120;
      MemoryMax = "1.5G";
      MemoryHigh = "1G";
      MemorySwapMax = "0B";
      IOWeight = 120;
      TasksMax = 512;
    };

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
