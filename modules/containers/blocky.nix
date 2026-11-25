{ config, lib, ... }:
let
  svc = config.hlamlab.services;
  settings = config.hlamlab.settings;
  splitHorizon = svc.blocky.enable && settings.lanAddress != null;
in
{
  # LAN DNS: Blocky blocks ads and trackers and answers the domain with the
  # host's LAN address. Unbound, in the same container, resolves everything
  # else from the root servers, so no outside resolver sees the queries.
  hlamlab.services.blocky = {
    ip = "10.0.0.12";
    # Blocky's HTTP port: metrics and API. DNS is on 53 (below).
    port = 4000;

    # No web UI.
    traefik.enable = false;
    # No state: the block lists download at each start, the cache is in RAM.
    zfs.enable = false;

    # Unbound asks the root and TLD servers, Blocky downloads its lists.
    internet = true;
    # The container's own lookups (the list downloads) go through Blocky.
    nameservers = [ "127.0.0.1" ];

    containerConfig = { ... }: {
      networking.firewall.allowedTCPPorts = [ 53 ];
      networking.firewall.allowedUDPPorts = [ 53 ];

      services.unbound = {
        enable = true;
        resolveLocalQueries = false;
        settings.server = {
          interface = [ "127.0.0.1@5335" ];
          prefetch = true;
          hide-identity = true;
          hide-version = true;
        };
      };

      services.blocky = {
        enable = true;
        settings = {
          ports = {
            dns = 53;
            http = svc.blocky.port;
          };
          upstreams.groups.default = [ "127.0.0.1:5335" ];
          # Resolves the list hosts at start, before Blocky itself answers.
          bootstrapDns = [ "127.0.0.1:5335" ];

          customDNS.mapping = lib.mkIf splitHorizon {
            ${settings.domain} = settings.lanAddress;
          };

          blocking = {
            # hagezi Pro: the level hagezi recommends; it blocks Google ad domains
            # too, which Normal keeps for working links in search results.
            # Entries are `*.domain`: Blocky matches a plain entry exactly, a
            # wildcard one with all subdomains.
            denylists.ads = [
              "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/pro.txt"
            ];
            clientGroupsBlock.default = [ "ads" ];
            loading = {
              # Answer at once; blocking starts when the lists are loaded.
              strategy = "fast";
              # A failed download waits for the next refresh (4h). Unbound
              # needs a few seconds for its first lookups from an empty cache.
              downloads = {
                attempts = 10;
                cooldown = "3s";
              };
            };
          };

          prometheus.enable = true;
        };
      };
      systemd.services.blocky = {
        wants = [ "unbound.service" ];
        after = [ "unbound.service" ];
      };
    };
  };

  # LAN devices ask the host; the host forwards to the container. The client
  # address stays as it is, so Blocky sees which device asks.
  networking.nat.forwardPorts = lib.mkIf svc.blocky.enable [
    { sourcePort = 53; proto = "udp"; destination = "${svc.blocky.ip}:53"; }
    { sourcePort = 53; proto = "tcp"; destination = "${svc.blocky.ip}:53"; }
  ];

  # Split horizon: at home, the domain resolves to the host and Traefik
  # answers on the LAN with the same certificate.
  networking.firewall.interfaces.${settings.lanInterface} = lib.mkIf splitHorizon {
    allowedTCPPorts = [ 443 ];
    # HTTP/3. Without it the browsers wait for QUIC to time out.
    allowedUDPPorts = [ 443 ];
  };
}
