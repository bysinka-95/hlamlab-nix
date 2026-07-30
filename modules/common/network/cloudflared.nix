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

  # Expose cloudflared's Prometheus metrics (the NixOS module has no native
  # option, so we set the env var on the generated tunnel unit). Bound to
  # 0.0.0.0 so the prometheus container can scrape it at 10.0.0.1:60123.
  systemd.services."cloudflared-tunnel-${config.hlamlab.settings.tunnelId}".environment.TUNNEL_METRICS = "0.0.0.0:60123";

  # Internal-only metrics port (not forwarded by the tunnel).
  networking.firewall.allowedTCPPorts = [ 60123 ];

  # Create directory for cloudflared certificates
  systemd.tmpfiles.rules = [
    "d /var/lib/cloudflared 0755 cloudflared cloudflared -"
  ];
}
