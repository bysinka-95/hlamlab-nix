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
      # The Traefik bouncer's LAPI key; registered by crowdsec-bouncer-register.
      crowdsec-bouncer-key = {
        key = "crowdsec/bouncer-key";
        owner = "traefik";
        group = "traefik";
        mode = "0400";
        restartUnits = [ "crowdsec-bouncer-register.service" "traefik.service" ];
      };
    };
  };
}
