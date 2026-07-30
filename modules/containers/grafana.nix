{ lib, config, ... }:
let
  hostConfig = config;
  domain = hostConfig.hlamlab.settings.domain;
in
{
  hlamlab.services.grafana = {
    ip = lib.mkDefault "10.0.0.9";
    port = lib.mkDefault 3000;
    domainPrefix = lib.mkDefault "grafana";

    storageQuota = lib.mkDefault "10G";
    storageReservation = lib.mkDefault "1G";

    cpuLimit = lib.mkDefault "100%";
    ramLimit = lib.mkDefault "768M";
    ramHigh = lib.mkDefault "512M";

    # Needs to reach Authelia over its public URL for the OIDC handshake.
    nameservers = [ "1.1.1.1" "1.0.0.1" ];

    bindMounts = {
      "/var/lib/grafana" = {
        hostPath = "/var/lib/services/grafana";
        isReadOnly = false;
      };
    };

    secrets = {
      grafana-oidc-secret = {
        key = "grafana/oidc-client-secret";
        restartUnits = [ "grafana.service" ];
      };
      # Break-glass local admin. Only usable if you temporarily flip
      # auth.disable_login_form back to false.
      grafana-admin-password = {
        key = "grafana/admin-password";
        restartUnits = [ "grafana.service" ];
      };
      # Grafana DB encryption key (no default in 26.05). Keep this stable —
      # rotating it orphans encrypted secrets in Grafana's DB.
      grafana-secret-key = {
        key = "grafana/secret-key";
        restartUnits = [ "grafana.service" ];
      };
    };

    containerConfig = { pkgs, config, ... }:
      let
        # Provisioned dashboards from grafana.com ship "__inputs" with a
        # ${DS_PROMETHEUS} / ${DS_LOKI} placeholder that only the UI import
        # wizard substitutes — file provisioning does not, hence the classic
        # "datasource ${DS_PROMETHEUS} not found". We pin the datasource UIDs
        # (below) and rewrite every dashboard JSON to those UIDs at build time.
        dashboards = pkgs.runCommand "grafana-dashboards" { } ''
          mkdir -p $out
          for f in ${./dashboards}/*.json; do
            ${pkgs.gnused}/bin/sed \
              -e 's/''${DS_PROMETHEUS}/prometheus/g' \
              -e 's/''${DS_LOKI}/loki/g' \
              "$f" > "$out/$(basename "$f")"
          done
        '';
      in
      {
        services.grafana = {
          enable = true;
          dataDir = "/var/lib/grafana";

          settings = {
            server = {
              http_addr = "0.0.0.0";
              http_port = 3000;
              domain = "grafana.${domain}";
              root_url = "https://grafana.${domain}/";
              enforce_domain = false;
            };

            # Break-glass only; login form disabled below.
            security.admin_password = "$__file{${config.sops.secrets.grafana-admin-password.path}}";
            security.secret_key = "$__file{${config.sops.secrets.grafana-secret-key.path}}";

            analytics.reporting_enabled = false;
            analytics.check_for_updates = false;

            users = {
              auto_assign_org = true;
              auto_assign_org_role = "Viewer";
            };

            # OIDC-only: no local login form, jump straight to Authelia.
            auth.disable_login_form = true;

            "auth.generic_oauth" = {
              enabled = true;
              name = "Authelia";
              icon = "signin";
              client_id = "grafana";
              client_secret = "$__file{${config.sops.secrets.grafana-oidc-secret.path}}";
              scopes = "openid profile email groups";
              empty_scopes = false;
              auth_url = "https://auth.${domain}/api/oidc/authorization";
              token_url = "https://auth.${domain}/api/oidc/token";
              api_url = "https://auth.${domain}/api/oidc/userinfo";
              login_attribute_path = "preferred_username";
              groups_attribute_path = "groups";
              name_attribute_path = "name";
              use_pkce = true;
              auto_login = true;
              # Server-admin requires this opt-in — without it OIDC users cap at
              # Org Admin and a null role lands them on Viewer (the bug you hit).
              allow_assign_grafana_admin = true;
              role_attribute_strict = true;
              role_attribute_path = "contains(groups[*], 'grafana-admins') && 'GrafanaAdmin' || contains(groups[*], 'grafana-editors') && 'Editor' || 'Viewer'";
            };
          };

          provision = {
            enable = true;

            datasources.settings = {
              apiVersion = 1;
              datasources = [
                {
                  name = "Prometheus";
                  type = "prometheus";
                  uid = "prometheus"; # pinned — dashboards rewritten to this UID
                  access = "proxy";
                  url = "http://10.0.0.10:9090";
                  isDefault = true;
                  jsonData.timeInterval = "15s";
                }
                {
                  name = "Loki";
                  type = "loki";
                  uid = "loki"; # pinned
                  access = "proxy";
                  url = "http://10.0.0.11:3100";
                }
              ];
            };

            dashboards.settings = {
              apiVersion = 1;
              providers = [{
                name = "default";
                options.path = dashboards;
                options.foldersFromFilesStructure = true;
                allowUiUpdates = false;
              }];
            };
          };
        };

        systemd.services.grafana.serviceConfig.StateDirectory = "grafana";
      };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/grafana 0750 - - -"
  ];
}
