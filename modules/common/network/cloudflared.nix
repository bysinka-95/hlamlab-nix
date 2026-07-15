{ config, ... }:

{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "${config.hlamlab.settings.tunnelId}" = {
        credentialsFile = config.sops.secrets.cloudflared-credentials.path;
        default = "http_status:404";

        ingress = {
          # Route root domain to Traefik HTTPS
          "${config.hlamlab.settings.domain}" = {
            service = "https://localhost:443";
            originRequest = {
              # Cloudflare Origin CA certificate for mTLS validation
              caPool = "/var/lib/cloudflared/origin-ca.pem";
              originServerName = config.hlamlab.settings.domain;
            };
          };

          # Route all subdomains to Traefik HTTPS
          "*.${config.hlamlab.settings.domain}" = {
            service = "https://localhost:443";
            originRequest = {
              caPool = "/var/lib/cloudflared/origin-ca.pem";
              originServerName = config.hlamlab.settings.domain;
            };
          };
        };
      };
    };
  };

  # Create directory for cloudflared certificates
  systemd.tmpfiles.rules = [
    "d /var/lib/cloudflared 0750 cloudflared traefik -"
  ];
}
