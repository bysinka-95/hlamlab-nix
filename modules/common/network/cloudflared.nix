{ config, ... }:
let
  vars = import ../settings.nix;
in
{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "${vars.tunnelId}" = {
        credentialsFile = config.sops.secrets.cloudflared-credentials.path;
        default = "http_status:404";

        ingress = {
          # Route root domain to Traefik HTTPS
          "${vars.domain}" = {
            service = "https://localhost:443";
            originRequest = {
              # Cloudflare Origin CA certificate for mTLS validation
              caPool = "/var/lib/cloudflared/origin-ca.pem";
              originServerName = vars.domain;
            };
          };

          # Route all subdomains to Traefik HTTPS
          "*.${vars.domain}" = {
            service = "https://localhost:443";
            originRequest = {
              caPool = "/var/lib/cloudflared/origin-ca.pem";
              originServerName = vars.domain;
            };
          };
        };
      };
    };
  };

  # Create directory for cloudflared certificates
  systemd.tmpfiles.rules = [
    "d /var/lib/cloudflared 0755 cloudflared cloudflared -"
  ];
}
