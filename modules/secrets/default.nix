{ ... }:
{
  # sops-nix secrets management configuration
  sops = {
    defaultSopsFile = ./secrets.yaml;
    defaultSopsFormat = "yaml";

    # The host decrypts with its SSH host key, converted to age on the fly —
    # that key is the host's recipient in .sops.yaml. Only the host decrypts:
    # containers get their own secrets as credentials (containers/frame.nix).
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # Cloudflare Tunnel credentials (JSON)
      cloudflared-credentials = {
        key = "cloudflare/credentials";
        owner = "cloudflared";
        group = "cloudflared";
        mode = "0400";
      };
      # Cloudflare API token for Let's Encrypt DNS-01 (Zone:DNS:Edit +
      # Zone:Zone:Read, this zone only). Read by Traefik via CF_DNS_API_TOKEN_FILE.
      cloudflare-dns-api-token = {
        key = "cloudflare/dns-api-token";
        owner = "traefik";
        group = "traefik";
        mode = "0400";
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
