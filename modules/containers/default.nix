{ config, ... }:
{
  # The host firewall is nftables: networking.firewall renders to it, and
  # the frame's per-container FORWARD rules need it. FORWARD drops by default;
  # the frame allows what each service declares (talksTo, internet).
  networking.nftables.enable = true;
  networking.firewall.filterForward = true;

  # NAT for the containers with `internet = true` (the frame lists them in
  # internalInterfaces).
  networking.nat = {
    enable = true;
    externalInterface = config.hlamlab.settings.lanInterface;
  };

  # Import service modules (each directory contains container + traefik + DNS + host integration)
  imports = [
    ./frame.nix
    ./opencloud.nix
    ./immich.nix
    ./collabora.nix
    ./authelia.nix
    ./lldap.nix
    ./vaultwarden.nix
    ./searx.nix
    ./grafana.nix
    ./prometheus.nix
    ./loki.nix
    ./blocky.nix
    ./gotify.nix
  ];
}
