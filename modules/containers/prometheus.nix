{ lib, config, ... }:
let
  hostConfig = config;
  nodePort = hostConfig.hlamlab.observability.nodeExporterPort;

  # Every enabled service container runs a node_exporter (injected by frame.nix).
  # Build one scrape target per container from its IP.
  enabledServices = lib.filterAttrs (n: v: v.enable) hostConfig.hlamlab.services;
  nodeTargets = lib.mapAttrsToList
    (name: svc: {
      labels.instance = name;
      targets = [ "${svc.ip}:${toString nodePort}" ];
    })
    enabledServices;
in
{
  hlamlab.services.prometheus = {
    ip = lib.mkDefault "10.0.0.10";
    port = lib.mkDefault 9090;
    domainPrefix = lib.mkDefault "prometheus";

    # 30d of metrics — size the dataset accordingly.
    storageQuota = lib.mkDefault "20G";
    storageReservation = lib.mkDefault "2G";

    cpuLimit = lib.mkDefault "100%";
    ramLimit = lib.mkDefault "1G";
    ramHigh = lib.mkDefault "512M";

    # Internal only — reached solely by Grafana. No public route.
    traefik.enable = lib.mkDefault false;

    bindMounts = {
      "/var/lib/prometheus2" = {
        hostPath = "/var/lib/services/prometheus";
        isReadOnly = false;
      };
    };

    containerConfig = { config, ... }: {
      services.prometheus = {
        enable = true;
        listenAddress = "0.0.0.0";
        port = 9090;
        retentionTime = "30d";
        stateDir = "prometheus2";

        scrapeConfigs = [
          {
            job_name = "node";
            static_configs = nodeTargets;
          }
          {
            job_name = "prometheus";
            static_configs = [{ targets = [ "127.0.0.1:9090" ]; }];
          }
          {
            job_name = "grafana";
            metrics_path = "/metrics";
            static_configs = [{ targets = [ "10.0.0.9:3000" ]; }];
          }
          {
            job_name = "loki";
            metrics_path = "/metrics";
            static_configs = [{ targets = [ "10.0.0.11:3100" ]; }];
          }
          {
            job_name = "authelia";
            static_configs = [{ targets = [ "10.0.0.5:9959" ]; }];
          }
          {
            # Traefik runs on the host; reachable from the container at the gateway IP.
            job_name = "traefik";
            static_configs = [{ targets = [ "10.0.0.1:8082" ]; }];
          }
          {
            # cloudflared runs on the host (TUNNEL_METRICS bound to 0.0.0.0:60123).
            job_name = "cloudflared";
            static_configs = [{ targets = [ "10.0.0.1:60123" ]; }];
          }
        ];
      };

      systemd.services.prometheus.serviceConfig.StateDirectory = "prometheus2";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/prometheus 0750 - - -"
  ];
}
