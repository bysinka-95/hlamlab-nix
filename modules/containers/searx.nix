{ config, ... }:
let
  svc = config.hlamlab.services;
in
{
  hlamlab.services.searx = {
    ip = "10.0.0.8";
    port = 8888;
    domainPrefix = "searxng";

    # It queries the search engines.
    internet = true;

    secrets = {
      searx-env = {
        key = "searx/env";
      };
    };

    containerConfig = { ... }:
      {
        services.searx = {
          enable = true;
          redisCreateLocally = true;
          configureUwsgi = true;
          environmentFile = svc.searx.secrets.searx-env.path;

          uwsgiConfig = {
            http = "0.0.0.0:${toString svc.searx.port}";
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
            botdetection = {
              ipv4_prefix = 32;
              ipv6_prefix = 56;
              # The client is the rightmost X-Forwarded-For entry that is not
              # one of these: Traefik (the containers' gateway) and the
              # cloudflared peer it appends. Traefik's real-ip middleware puts
              # the CF-Connecting-IP in front of them.
              trusted_proxies = [ "10.0.0.1/32" "127.0.0.0/8" "::1/128" ];
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
              base_url = svc.searx.baseUrl;
              port = svc.searx.port;
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

}
