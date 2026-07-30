{ lib, config, ... }:
let
  hostConfig = config;
in
{
  hlamlab.services.loki = {
    ip = lib.mkDefault "10.0.0.11";
    port = lib.mkDefault 3100;
    domainPrefix = lib.mkDefault "loki";

    storageQuota = lib.mkDefault "20G";
    storageReservation = lib.mkDefault "2G";

    cpuLimit = lib.mkDefault "100%";
    ramLimit = lib.mkDefault "512M";
    ramHigh = lib.mkDefault "256M";

    # Internal only — receives pushes from the host Alloy, queried by Grafana.
    traefik.enable = lib.mkDefault false;

    bindMounts = {
      "/var/lib/loki" = {
        hostPath = "/var/lib/services/loki";
        isReadOnly = false;
      };
    };

    containerConfig = { ... }: {
      services.loki = {
        enable = true;
        dataDir = "/var/lib/loki";
        configuration = {
          auth_enabled = false;

          server = {
            http_listen_address = "0.0.0.0";
            http_listen_port = 3100;
            grpc_listen_port = 9096;
            log_level = "info";
          };

          common = {
            path_prefix = "/var/lib/loki";
            replication_factor = 1;
            instance_addr = "127.0.0.1";
            ring.kvstore.store = "inmemory";
            storage.filesystem = {
              chunks_directory = "/var/lib/loki/chunks";
              rules_directory = "/var/lib/loki/rules";
            };
          };

          schema_config.configs = [{
            from = "2024-01-01";
            store = "tsdb";
            object_store = "filesystem";
            schema = "v13";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }];

          # 30d log retention, enforced by the compactor.
          limits_config = {
            retention_period = "720h";
            reject_old_samples = true;
            reject_old_samples_max_age = "168h";
            ingestion_rate_mb = 8;
            ingestion_burst_size_mb = 16;
          };

          compactor = {
            working_directory = "/var/lib/loki/compactor";
            retention_enabled = true;
            delete_request_store = "filesystem";
          };

          analytics.reporting_enabled = false;
        };
      };

      systemd.services.loki.serviceConfig.StateDirectory = "loki";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/loki 0750 - - -"
  ];
}
