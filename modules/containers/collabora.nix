{ config, ... }:
let
  svc = config.hlamlab.services;
in
{
  hlamlab.services.collabora = {
    ip = "10.0.0.4";
    port = 9980;
    storageQuota = "20G";
    storageReservation = "5G";

    ramLimit = "1.5G";
    ramHigh = "1G";

    # coolwsd runs as `cool` and keeps its child-roots and systemplate under
    # /var/lib/cool, not under a directory named after the service.
    serviceUser = "cool";
    dataDir = "/var/lib/cool";

    traefikMiddlewares = [ "collabora-headers" ];

    containerConfig = { ... }: {
      services.collabora-online = {
        enable = true;
        port = svc.collabora.port;

        settings = {
          ssl = {
            enable = false;
            termination = true;
          };

          storage.wopi = {
            "@allow" = true;
            host = [ svc.opencloud.fqdn ];
          };

          server_name = svc.collabora.fqdn;
        };
      };
    };
  };

  # Collabora renders inside an OpenCloud iframe, so it needs the one thing
  # `security-headers` forbids: a frame-ancestors exception.
  services.traefik.dynamicConfigOptions.http.middlewares.collabora-headers = {
    headers = {
      sslRedirect = true;
      frameDeny = false;
      customFrameOptionsValue = "ALLOW-FROM ${svc.opencloud.baseUrl}";
      contentSecurityPolicy = "frame-ancestors 'self' ${svc.opencloud.baseUrl}";
      contentTypeNosniff = true;
      browserXssFilter = true;
    };
  };
}
