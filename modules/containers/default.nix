{ config, ... }:
{
  # The host firewall is nftables: networking.firewall renders to it, and
  # the frame's per-container FORWARD rules need it.
  networking.nftables.enable = true;

  # NAT so containers can reach the outside world. By source address, not
  # interface: `ve-+` is an iptables wildcard the nftables backend would
  # render literally, matching nothing.
  networking.nat = {
    enable = true;
    internalIPs = [ "10.0.0.0/24" ];
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
  ];
}
