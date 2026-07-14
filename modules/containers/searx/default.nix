{ config, ... }:
let
  vars = import ../../common/settings.nix;
in
{
  hlamlab.services.searx = {
    ip = "10.0.0.8";
    port = 8888;
    domainPrefix = "searxng";
    storageQuota = "10G";
    storageReservation = "1G";
    
    bindMounts = {
      "/var/lib/searx" = {
        hostPath = "/var/lib/services/searx";
        isReadOnly = false;
      };
    };

    secrets = {
      "searx/env" = {
        key = "searx/env";
        restartUnits = [ "uwsgi.service" ];
      };
    };

    containerConfig = { lib, pkgs, config, ... }: {
      systemd.services.uwsgi.serviceConfig.StateDirectory = "searx";
      systemd.services.uwsgi.serviceConfig.EnvironmentFile = config.sops.secrets."searx/env".path;

      services.searx = {
        enable = true;
        redisCreateLocally = true;
        configureUwsgi = true;
        environmentFile = config.sops.secrets."searx/env".path;

        uwsgiConfig = {
          http = "0.0.0.0:8888";
        };

        faviconsSettings = {
          favicons = {
            cfg_schema = 1;
            cache = {
              db_url = "/var/lib/searx/faviconcache.db";
            };
          };
        };

        limiterSettings = {
          real_ip = {
            x_for = 1;
            ipv4_prefix = 32;
            ipv6_prefix = 56;
          };
          botdetection = {
            ip_limit = {
              filter_link_local = true;
              link_token = true;
            };
          };
        };

        settings = {
          general = {
            debug = false;
            instance_name = "SearXNG Instance";
            donation_url = false;
            contact_url = false;
            privacypolicy_url = false;
            enable_metrics = false;
          };

          ui = {
            static_use_hash = true;
            default_locale = "en";
            query_in_title = true;
            infinite_scroll = false;
            center_alignment = true;
            default_theme = "simple";
            theme_args.simple_style = "auto";
            search_on_category_select = false;
            hotkeys = "vim";
          };

          search = {
            safe_search = 2;
            autocomplete_min = 2;
            autocomplete = "duckduckgo";
            ban_time_on_fail = 5;
            max_ban_time_on_fail = 120;
            favicon_resolver = "duckduckgo";
          };

          server = {
            base_url = "https://searxng.${vars.domain}";
            port = 8888;
            bind_address = "0.0.0.0";
            secret_key = "$SEARX_SECRET_KEY";
            limiter = true;
            public_instance = true;
            image_proxy = true;
            method = "GET";
          };

          outgoing = {
            request_timeout = 5.0;
            max_request_timeout = 15.0;
            pool_connections = 100;
            pool_maxsize = 15;
            enable_http2 = true;
          };

          enabled_plugins = [
            "Basic Calculator"
            "Hash plugin"
            "Tor check plugin"
            "Open Access DOI rewrite"
            "Hostnames plugin"
            "Unit converter plugin"
            "Tracker URL remover"
          ];
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/services/searx 0750 root root -"
  ];
}
