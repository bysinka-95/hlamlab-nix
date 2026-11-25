{ config, lib, ... }:
let
  svc = config.hlamlab.services;
  settings = config.hlamlab.settings;
  enabled = lib.filterAttrs (_: s: s.enable) svc;

  alerts = [{ type = "gotify"; }];

  # Each published service, by its public name: the container resolves it to
  # Traefik on the host, so a check takes the path of a real request.
  webChecks = lib.mapAttrsToList
    (name: s: {
      inherit name alerts;
      group = "services";
      url = s.baseUrl;
      interval = "1m";
      # Sign-in pages redirect; Gatus follows to the final page. Behind the
      # Authelia gate, 401 shows the gate is up and turns strangers away.
      # A failed connection gives status 0.
      conditions =
        if lib.elem "authelia" s.traefikMiddlewares
        then [ "[STATUS] == 401" ]
        else [ "[STATUS] >= 200" "[STATUS] < 400" ];
    })
    (lib.filterAttrs (name: s: s.traefik.enable && name != "gatus") enabled);

  # Let's Encrypt renews 30 days before expiry: 10 days left means the
  # renewal has failed for about 20 days.
  certCheck = {
    name = "certificate";
    group = "host";
    url = svc.authelia.baseUrl;
    interval = "1h";
    conditions = [ "[CERTIFICATE_EXPIRATION] > 240h" ];
    inherit alerts;
  };

  dnsChecks = lib.optionals (enabled ? blocky) [
    {
      name = "dns-domain";
      group = "dns";
      url = svc.blocky.ip;
      dns = { query-name = settings.domain; query-type = "A"; };
      conditions = [ "[DNS_RCODE] == NOERROR" ]
        ++ lib.optional (settings.lanAddress != null) "[BODY] == ${settings.lanAddress}";
      inherit alerts;
    }
    {
      # Unbound resolves from the root servers.
      name = "dns-recursion";
      group = "dns";
      url = svc.blocky.ip;
      dns = { query-name = "example.com"; query-type = "A"; };
      conditions = [ "[DNS_RCODE] == NOERROR" ];
      inherit alerts;
    }
  ];
in
{
  # Checks each service from the outside and sends failures to Gotify. The
  # status page is an admin UI: Authelia, group admins, two factors.
  hlamlab.services.gatus = {
    ip = "10.0.0.14";
    port = 8080;
    domainPrefix = "status";
    traefikMiddlewares = [ "authelia" "security-headers" ];

    # History is in memory: a restart starts it again.
    zfs.enable = false;
    ramLimit = "256M";
    ramHigh = "192M";

    secrets = {
      # GOTIFY_TOKEN=<token of the Gatus app in Gotify>
      gatus-env = {
        key = "gatus/env";
      };
    };

    containerConfig = { ... }: {
      services.gatus = {
        enable = true;
        environmentFile = svc.gatus.secrets.gatus-env.path;
        settings = {
          web.port = svc.gatus.port;
          alerting.gotify = {
            server-url = svc.gotify.baseUrl;
            token = "\${GOTIFY_TOKEN}";
            title = "hlamlab";
            default-alert = {
              failure-threshold = 3;
              success-threshold = 2;
              send-on-resolved = true;
            };
          };
          endpoints = webChecks ++ [ certCheck ] ++ dnsChecks;
        };
      };
    };
  };

  # DNS checks are UDP; talksTo opens TCP only.
  networking.firewall.extraForwardRules = lib.mkIf (svc.gatus.enable && svc.blocky.enable) ''
    iifname "ve-gatus" oifname "ve-blocky" udp dport 53 accept
  '';
}
