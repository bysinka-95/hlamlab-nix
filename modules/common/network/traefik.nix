{ config, pkgs, ... }:
let
  domain = config.hlamlab.settings.domain;
in
{
  services.traefik = {
    enable = true;

    # Static Configuration
    staticConfigOptions = {
      global = {
        checkNewVersion = false;
        sendAnonymousUsage = false;
      };

      # API and Dashboard
      api = {
        dashboard = true;
        insecure = false; # Served only through the dashboard router below
      };

      # Logging
      log = {
        level = "INFO";
        filePath = "/var/log/traefik/traefik.log";
      };

      accessLog = {
        filePath = "/var/log/traefik/access.log";
        format = "json";
        filters = {
          statusCodes = [ "200-299" "400-599" ];
        };
        bufferingSize = 0;
        fields = {
          headers = {
            defaultMode = "drop";
            names = {
              User-Agent = "keep";
            };
          };
        };
      };

      # Prometheus metrics (scraped by the prometheus container at 10.0.0.1:8082)
      metrics = {
        prometheus = {
          entryPoint = "metrics";
          addEntryPointsLabels = true;
          addServicesLabels = true;
          addRoutersLabels = true;
        };
      };

      # Entry Points
      entryPoints = {
        # Internal-only metrics endpoint (not routed by cloudflared).
        metrics = {
          address = ":8082";
        };

        # The only public entrypoint. cloudflared is its sole public client and
        # connects over loopback; containers reach it at the gateway address
        # (hairpin). No :80 — nothing outside the tunnel ever spoke plain HTTP.
        https = {
          address = ":443";
          # Only cloudflared's X-Forwarded-For is kept (Cloudflare appends the
          # real client IP to it). Containers are not trusted: they could forge
          # any client IP.
          forwardedHeaders = {
            trustedIPs = [ "127.0.0.1/32" "::1/128" ];
          };
          # Ahead of every router's own middlewares, the dashboard's included.
          http.middlewares = [ "real-ip@file" ];
          # TLS for every router on this entrypoint. Routers must not carry
          # their own `tls` block: even an empty one replaces this whole section.
          http.tls = {
            certResolver = "letsencrypt";
            # One wildcard, no per-host certificates — keeps service names out
            # of Certificate Transparency logs.
            domains = [{ main = domain; sans = [ "*.${domain}" ]; }];
          };
        };
      };

      # Local plugin, read from ./plugins-local/src/<moduleName> under the
      # service's working directory (/var/lib/traefik; tmpfiles link below).
      experimental.localPlugins.realip.moduleName = "hlamlab/realip";

      # Providers
      providers = {
        providersThrottleDuration = "2s";
      };

      # Let's Encrypt via DNS-01: needs no inbound port, so it works behind the
      # tunnel, and its certificate is trusted by every runtime in every
      # container (the hairpin path depends on that).
      certificatesResolvers.letsencrypt.acme = {
        storage = "/var/lib/traefik/acme.json";
        dnsChallenge = {
          provider = "cloudflare";
          # lego checks the TXT record's propagation through these instead of
          # the host's resolver: a home router's DNS forwarder may not answer
          # TXT queries at all (UTM's doesn't), and the check then times out.
          resolvers = [ "1.1.1.1:53" "1.0.0.1:53" ];
        };
      };
    };

    # Dynamic Configuration (native Nix instead of YAML files)
    dynamicConfigOptions = {
      http = {
        middlewares = {
          # The client IP from Cloudflare's CF-Connecting-IP, trusted only from
          # cloudflared. Authelia and the apps read the first X-Forwarded-For
          # element, which the client controls; this pins it to the real one.
          real-ip.plugin.realip.trustedIPs = [ "127.0.0.1/32" "::1/128" ];

          # Security headers middleware (shared by all services)
          security-headers = {
            headers = {
              frameDeny = true;
              sslRedirect = true;
              browserXssFilter = true;
              contentTypeNosniff = true;
              forceSTSHeader = true;
              stsIncludeSubdomains = true;
              stsPreload = true;
              stsSeconds = 31536000;
              customFrameOptionsValue = "SAMEORIGIN";
            };
          };
        };

        routers = {
          # Traefik dashboard router
          dashboard = {
            rule = "Host(`traefik.${domain}`)";
            service = "api@internal";
            entryPoints = [ "https" ];
            # Authelia's gate, `admins` only (containers/authelia.nix).
            middlewares = [ "authelia" "security-headers" ];
          };
        };
      };
    };
  };

  systemd.services.traefik = {
    # /var/log/traefik, with proper permissions. State (acme.json) lives in the
    # module's own dataDir, /var/lib/traefik.
    serviceConfig.LogsDirectory = "traefik";
    # lego's `_FILE` convention: the token never enters the nix store or the
    # unit's environment.
    environment.CF_DNS_API_TOKEN_FILE = config.sops.secrets.cloudflare-dns-api-token.path;
    # Local plugins are read from ./plugins-local under the working directory
    # (/var/lib/traefik). Linked at start, as traefik, so a plugin change
    # changes the unit and restarts Traefik.
    preStart = ''
      ln -sfn ${pkgs.linkFarm "traefik-plugins-local" [
        { name = "src/hlamlab/realip"; path = ./traefik-plugins/realip; }
      ]} /var/lib/traefik/plugins-local
    '';
  };

  # 443 from containers only (hairpin); cloudflared reaches it over loopback,
  # so the LAN never needs it. Metrics on 8082 for the prometheus container.
  networking.firewall.extraInputRules = ''
    iifname "ve-*" tcp dport 443 accept
  '';
  networking.firewall.interfaces."ve-prometheus".allowedTCPPorts = [ 8082 ];
}
