{ lib, config, ... }:
let
  svc = config.hlamlab.services;

  # One scrape target per enabled container's restricted node_exporter (injected
  # by frame.nix). These carry systemd unit state, the container's own filesystem
  # usage and its netns counters — nothing that duplicates the host exporter.
  containerNodeTargets = lib.mapAttrsToList
    (name: s: {
      labels.instance = name;
      targets = [ "${s.ip}:9101" ];
    })
    (lib.filterAttrs (n: s: s.enable) svc);
in
{
  hlamlab.services.prometheus = {
    ip = "10.0.0.10";
    port = 9090;

    # 30d of metrics — size the dataset accordingly.
    storageQuota = "20G";
    storageReservation = "2G";

    # Internal only — reached solely by Grafana. No public route.
    traefik.enable = false;

    # Scrape targets inside other containers (the per-container node
    # exporters on :9101 are allowed by the frame itself).
    talksTo = {
      authelia = [ 9959 ];
      grafana = [ svc.grafana.port ];
      loki = [ svc.loki.port ];
    };

    dataDir = "/var/lib/prometheus2";

    containerConfig = { ... }: {
      services.prometheus = {
        enable = true;
        listenAddress = "0.0.0.0";
        port = svc.prometheus.port;
        retentionTime = "30d";
        stateDir = "prometheus2";

        # 15s default scrape — matches Grafana's datasource timeInterval so
        # $__rate_interval (>= 4x scrape) covers enough samples for rate() to
        # resolve. At the Prometheus 1m default, rate() over a 1m window caught
        # a single cAdvisor sample and returned empty (CPU/net/disk panels).
        globalConfig.scrape_interval = "15s";

        # Everything on the host is reachable from the container at the gateway
        # address 10.0.0.1.
        scrapeConfigs = [
          {
            # One node_exporter for the machine. Containers share the host
            # kernel, so a per-container exporter would only repeat these numbers
            # — real per-container usage comes from cAdvisor below.
            job_name = "node";
            static_configs = [{
              targets = [ "10.0.0.1:9100" ];
              labels.instance = "playground";
            }];
          }
          {
            # Per-container systemd unit state / filesystem / netdev. Separate job
            # so the node-exporter-full dashboard, which picks its instances from
            # node_uname_info, keeps listing only the host.
            job_name = "node-container";
            static_configs = containerNodeTargets;
          }
          {
            # Per-container CPU / memory / network / IO from the host cgroup tree.
            job_name = "cadvisor";
            static_configs = [{ targets = [ "10.0.0.1:8080" ]; }];
          }
          {
            job_name = "traefik";
            static_configs = [{ targets = [ "10.0.0.1:8082" ]; }];
          }
          {
            # cloudflared (TUNNEL_METRICS bound to 0.0.0.0:60123).
            job_name = "cloudflared";
            static_configs = [{ targets = [ "10.0.0.1:60123" ]; }];
          }
          {
            job_name = "crowdsec";
            static_configs = [{ targets = [ "10.0.0.1:6060" ]; }];
          }
          {
            job_name = "prometheus";
            static_configs = [{ targets = [ "127.0.0.1:${toString svc.prometheus.port}" ]; }];
          }
          {
            job_name = "grafana";
            metrics_path = "/metrics";
            static_configs = [{ targets = [ svc.grafana.address ]; }];
          }
          {
            job_name = "loki";
            metrics_path = "/metrics";
            static_configs = [{ targets = [ svc.loki.address ]; }];
          }
          {
            job_name = "authelia";
            static_configs = [{ targets = [ "${svc.authelia.ip}:9959" ]; }];
          }
        ];
      };
    };
  };
}
