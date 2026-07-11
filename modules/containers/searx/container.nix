{ config, lib, ... }:
let
  vars = import ../../common/local.nix;
in
{
  containers.searx = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.8";

    bindMounts = {
      "/var/lib/searx" = {
        hostPath = "/var/lib/services/searx";
        isReadOnly = false;
      };
      "/run/secrets/searx-env" = {
        hostPath = config.sops.secrets.searx-env.path;
        isReadOnly = true;
      };
    };

    config = { lib, pkgs, ... }: {
      networking.firewall.allowedTCPPorts = [ 8888 ];
      networking.nameservers = [ "1.1.1.1" "1.0.0.1" ];

      # Force searx user/group to have static UID/GID 905 to match host
      users.users.searx = {
        isSystemUser = true;
        group = "searx";
        uid = 905;
      };
      users.groups.searx = {
        gid = 905;
      };

      # Pass the sops environment file containing SEARX_SECRET_KEY to uwsgi
      systemd.services.uwsgi.serviceConfig.EnvironmentFile = "/run/secrets/searx-env";

      services.searx = {
        enable = true;
        redisCreateLocally = true;
        configureUwsgi = true;

        uwsgiConfig = {
          http = "0.0.0.0:8888";
        };

        # Load the secret from the mounted sops secret file
        environmentFile = "/run/secrets/searx-env";

        # Favicons settings for SearXNG
        faviconsSettings = {
          favicons = {
            cfg_schema = 1;
            cache = {
              db_url = "/var/lib/searx/faviconcache.db";
            };
          };
        };

        # Advanced rate limiting as recommended by NixOS Wiki
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
          # Instance settings
          general = {
            debug = false;
            instance_name = "SearXNG Instance";
            donation_url = false;
            contact_url = false;
            privacypolicy_url = false;
            enable_metrics = false;
          };

          # User interface
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

          # Search engine settings
          search = {
            safe_search = 2;
            autocomplete_min = 2;
            autocomplete = "duckduckgo";
            ban_time_on_fail = 5;
            max_ban_time_on_fail = 120;
            favicon_resolver = "duckduckgo";
          };

          # Server configuration
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

          # Search engines overrides
#          engines = lib.mapAttrsToList (name: value: { inherit name; } // value) {
#            "duckduckgo".disabled = true;
#            "brave".disabled = true;
#            "bing".disabled = false;
#            "mojeek".disabled = true;
#            "mwmbl".disabled = false;
#            "mwmbl".weight = 0.4;
#            "qwant".disabled = true;
#            "crowdview".disabled = false;
#            "crowdview".weight = 0.5;
#            "curlie".disabled = true;
#            "ddg definitions".disabled = false;
#            "ddg definitions".weight = 2;
#            "wikibooks".disabled = false;
#            "wikidata".disabled = false;
#            "wikiquote".disabled = true;
#            "wikisource".disabled = true;
#            "wikispecies".disabled = false;
#            "wikispecies".weight = 0.5;
#            "wikiversity".disabled = false;
#            "wikiversity".weight = 0.5;
#            "wikivoyage".disabled = false;
#            "wikivoyage".weight = 0.5;
#            "currency".disabled = true;
#            "dictzone".disabled = true;
#            "lingva".disabled = true;
#            "bing images".disabled = false;
#            "brave.images".disabled = true;
#            "duckduckgo images".disabled = true;
#            "google images".disabled = false;
#            "qwant images".disabled = true;
#            "1x".disabled = true;
#            "artic".disabled = false;
#            "deviantart".disabled = false;
#            "flickr".disabled = true;
#            "imgur".disabled = false;
#            "library of congress".disabled = false;
#            "material icons".disabled = true;
#            "material icons".weight = 0.2;
#            "openverse".disabled = false;
#            "pinterest".disabled = true;
#            "svgrepo".disabled = false;
#            "unsplash".disabled = false;
#            "wallhaven".disabled = false;
#            "wikicommons.images".disabled = false;
#            "yacy images".disabled = true;
#            "bing videos".disabled = false;
#            "brave.videos".disabled = true;
#            "duckduckgo videos".disabled = true;
#            "google videos".disabled = false;
#            "qwant videos".disabled = false;
#            "dailymotion".disabled = true;
#            "google play movies".disabled = true;
#            "invidious".disabled = true;
#            "odysee".disabled = true;
#            "peertube".disabled = false;
#            "piped".disabled = true;
#            "rumble".disabled = false;
#            "sepiasearch".disabled = false;
#            "vimeo".disabled = true;
#            "youtube".disabled = false;
#            "brave.news".disabled = true;
#            "google news".disabled = true;
#          };

          # Outgoing requests
          outgoing = {
            request_timeout = 5.0;
            max_request_timeout = 15.0;
            pool_connections = 100;
            pool_maxsize = 15;
            enable_http2 = true;
          };

          # Enabled plugins
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

      system.stateVersion = "26.05";
    };
  };

  # Host side tmpfiles rule for persistent state directory
  systemd.tmpfiles.rules = [
    "d /var/lib/services/searx 0750 905 905 -"
  ];
}
