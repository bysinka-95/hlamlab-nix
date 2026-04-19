{ ... }:
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
      cloudflared-credentials = {
        owner = "cloudflared";
        group = "cloudflared";
        mode = "0400";
      };
      # Cloudflare's Authenticated Origin Pull CA (public certificate)
      cloudflare-origin-ca = {
        # World-readable since it's a public CA cert (both cloudflared and traefik need it)
        mode = "0444";
        path = "/var/lib/cloudflared/origin-ca.pem";
      };
      # YOUR origin certificate (what Traefik presents to Cloudflare)
      traefik-origin-cert = {
        owner = "traefik";
        group = "traefik";
        mode = "0400";
        path = "/var/lib/traefik/certs/origin.crt";
      };
      # YOUR origin private key (Traefik's private key)
      traefik-origin-key = {
        owner = "traefik";
        group = "traefik";
        mode = "0400";
        path = "/var/lib/traefik/certs/origin.key";
      };
      # Authentik environment file for database/redis passwords and secret key
      authentik-env = {
        # Readable only by root (systemd reads EnvironmentFile before dropping privileges)
        mode = "0400";
      };
    };
  };
}
