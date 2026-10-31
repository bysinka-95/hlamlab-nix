{ config, ... }:
let
  svc = config.hlamlab.services;
in
{
  hlamlab.services.grafana = {
    ip = "10.0.0.9";
    port = 3000;

    ramLimit = "768M";

    # Its two datasources.
    talksTo = {
      prometheus = [ svc.prometheus.port ];
      loki = [ svc.loki.port ];
    };

    secrets = {
      grafana-oidc-secret = {
        key = "grafana/oidc-client-secret";
        unit = "grafana.service";
      };
      # Break-glass local admin. Only usable if you temporarily flip
      # auth.disable_login_form back to false.
      grafana-admin-password = {
        key = "grafana/admin-password";
        unit = "grafana.service";
      };
      # Grafana DB encryption key (no default in 26.05). Keep this stable —
      # rotating it orphans encrypted secrets in Grafana's DB.
      grafana-secret-key = {
        key = "grafana/secret-key";
        unit = "grafana.service";
      };
    };

    containerConfig = { pkgs, ... }:
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
              http_port = svc.grafana.port;
              domain = svc.grafana.fqdn;
              root_url = "${svc.grafana.baseUrl}/";
              enforce_domain = false;
            };

            # Break-glass only; login form disabled below.
            security.admin_password = "$__file{${svc.grafana.secrets.grafana-admin-password.path}}";
            security.secret_key = "$__file{${svc.grafana.secrets.grafana-secret-key.path}}";

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
              client_secret = "$__file{${svc.grafana.secrets.grafana-oidc-secret.path}}";
              scopes = "openid profile email groups";
              empty_scopes = false;
              auth_url = "${svc.authelia.baseUrl}/api/oidc/authorization";
              token_url = "${svc.authelia.baseUrl}/api/oidc/token";
              api_url = "${svc.authelia.baseUrl}/api/oidc/userinfo";
              login_attribute_path = "preferred_username";
              groups_attribute_path = "groups";
              name_attribute_path = "name";
              use_pkce = true;
              auto_login = true;
              # Server-admin requires this opt-in — without it OIDC users cap at
              # Org Admin and a null role lands them on Viewer (the bug you hit).
              allow_assign_grafana_admin = true;
              role_attribute_strict = true;
              # `admins` is declared in lldap.nix.
              role_attribute_path = "contains(groups[*], 'admins') && 'GrafanaAdmin' || 'Viewer'";
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
                  url = "http://${svc.prometheus.address}";
                  isDefault = true;
                  jsonData.timeInterval = "15s";
                }
                {
                  name = "Loki";
                  type = "loki";
                  uid = "loki"; # pinned
                  access = "proxy";
                  url = "http://${svc.loki.address}";
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

      };
  };

}
