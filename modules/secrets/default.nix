{ ... }:
let
  vars = import ../common/settings.nix;
in
{
  # sops-nix secrets management configuration
  sops = {
    defaultSopsFile = ./secrets.yaml;
    defaultSopsFormat = "yaml";

    # Use age for encryption (SSH keys can be converted to age keys)
    age = {
      # This will be the age key derived from the host's SSH key
      keyFile = "/var/lib/sops-nix/key.txt";
      # Automatically generate the age key from SSH host key if it doesn't exist
      generateKey = true;
      sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };

    secrets = {
      # Cloudflare Tunnel credentials (JSON)
      cloudflared-credentials = {
        key = "cloudflare/credentials";
        owner = "cloudflared";
        group = "cloudflared";
        mode = "0400";
      };
      # Cloudflare's Authenticated Origin Pull CA (public certificate)
      cloudflare-origin-ca = {
        key = "cloudflare/origin-ca";
        mode = "0444";
        path = "/var/lib/cloudflared/origin-ca.pem";
        restartUnits = [ "traefik.service" ];
      };
      # YOUR origin certificate (what Traefik presents to Cloudflare)
      traefik-origin-cert = {
        key = "traefik/origin-cert";
        owner = "traefik";
        group = "traefik";
        mode = "0400";
        path = "/var/lib/traefik/certs/origin.crt";
        restartUnits = [ "traefik.service" ];
      };
      # YOUR origin private key (Traefik's private key)
      traefik-origin-key = {
        key = "traefik/origin-key";
        owner = "traefik";
        group = "traefik";
        mode = "0400";
        path = "/var/lib/traefik/certs/origin.key";
        restartUnits = [ "traefik.service" ];
      };
      # Traefik dashboard basic auth credentials
      traefik-dashboard-auth = {
        key = "traefik/dashboard-auth";
        owner = "traefik";
        group = "traefik";
        mode = "0400";
        path = "/var/lib/traefik/dashboard-auth";
        restartUnits = [ "traefik.service" ];
      };
    };
  };
}
