{ config, lib, ... }:
let
  authelia = config.hlamlab.services.authelia.enable or false;
  authelia-journal = "/var/lib/nixos-containers/authelia/var/log/journal";
in
{
  # Detection: CrowdSec reads Traefik's access log (every request through the
  # tunnel) and Authelia's journal (every login). Remediation is the Traefik
  # bouncer, which asks the LAPI below.
  services.crowdsec = {
    enable = true;

    hub = {
      collections = [
        "crowdsecurity/traefik"
        "crowdsecurity/http-cve"
        "crowdsecurity/base-http-scenarios"
        "crowdsecurity/appsec-virtual-patching"
        "crowdsecurity/appsec-generic-rules"
      ] ++ lib.optional authelia "LePresidente/authelia";
      parsers = [
        # Stage 0 for the journal, then timestamps and GeoIP — the parts of
        # crowdsecurity/linux these sources need, without sshd.
        "crowdsecurity/syslog-logs"
        "crowdsecurity/dateparse-enrich"
        "crowdsecurity/geoip-enrich"
        # Loopback and private ranges: hairpin traffic from the containers is
        # never banned.
        "crowdsecurity/whitelists"
      ];
      appsec-configs = [ "crowdsecurity/appsec-default" ];
    };

    # The access log is the traefik group's; the journal group is a module default.
    extraGroups = [ "traefik" ];
    # "-": missing is fine — before the container's first start, or on a host
    # without Authelia.
    readOnlyPaths = lib.optional authelia "-${authelia-journal}";

    settings = {
      # The Central API (community blocklist) stays off, the module default:
      # nothing about this host or its visitors leaves it.
      # cAdvisor holds :8080.
      config.api.server.listen_uri = "127.0.0.1:8180";
      # Metrics, for the prometheus container only (firewall below).
      config.prometheus = {
        enabled = true;
        level = "full";
        listen_addr = "0.0.0.0";
        listen_port = 6060;
      };

      acquisitions = [
        {
          filenames = [ "/var/log/traefik/access.log" ];
          labels.type = "traefik";
        }
      ] ++ lib.optional authelia {
        source = "journalctl";
        journalctl_filter = [ "--directory=${authelia-journal}" "_SYSTEMD_UNIT=authelia-main.service" ];
        labels.type = "syslog";
      } ++ [
        # Inline request inspection for the Traefik bouncer (Task 12).
        {
          source = "appsec";
          listen_addr = "127.0.0.1:7422";
          appsec_config = "crowdsecurity/appsec-default";
          name = "appsec";
          labels.type = "appsec";
        }
      ];

      # Stage 0 for everything that is not syslog (the access log, AppSec):
      # the source's type label becomes the program the parsers match on. The
      # hub no longer ships crowdsecurity/non-syslog; this is its body.
      parsers.s00Raw = [{
        name = "hlamlab/non-syslog";
        filter = "evt.Line.Labels.type != 'syslog'";
        onsuccess = "next_stage";
        statics = [
          { parsed = "message"; expression = "evt.Line.Raw"; }
          { parsed = "program"; expression = "evt.Line.Labels.type"; }
          { meta = "datasource_path"; expression = "evt.Line.Src"; }
          { meta = "datasource_type"; expression = "evt.Line.Module"; }
        ];
      }];

      # CrowdSec's stock profiles: an alert on an IP or a range becomes a 4h ban.
      # Without profiles alerts never turn into decisions.
      profiles = map
        (scope: {
          name = "default_${scope}_remediation";
          filters = [ ''Alert.Remediation == true && Alert.GetScope() == "${if scope == "ip" then "Ip" else "Range"}"'' ];
          decisions = [{ type = "ban"; duration = "4h"; }];
          on_success = "break";
        })
        [ "ip" "range" ];
    };
  };

  # Remediation: every request passes this middleware first (traefik.nix
  # entrypoint). It fails open — a CrowdSec outage must not take the sites down.
  services.traefik.dynamicConfigOptions.http.middlewares.crowdsec.plugin.bouncer = {
    enabled = true;
    crowdsecMode = "stream";
    crowdsecLapiHost = "127.0.0.1:8180";
    crowdsecLapiKeyFile = config.sops.secrets.crowdsec-bouncer-key.path;
    # The client is CF-Connecting-IP, believed only from cloudflared; the
    # containers' hairpin traffic is never checked.
    forwardedHeadersTrustedIps = [ "127.0.0.1/32" "::1/128" ];
    forwardedHeadersCustomName = "CF-Connecting-IP";
    clientTrustedIps = [ "10.0.0.0/24" ];
    crowdsecAppsecEnabled = true;
    crowdsecAppsecHost = "127.0.0.1:7422";
    crowdsecAppsecFailureBlock = false;
    crowdsecAppsecUnreachableBlock = false;
    updateMaxFailure = -1;
    # Otherwise Traefik waits for CrowdSec at start.
    streamStartupBlock = false;
  };

  # Registers the bouncer's key (delete + add, so a rotated key takes effect;
  # the sops secret restarts this unit). Runs as crowdsec: cscli writes the
  # LAPI database directly.
  systemd.services.crowdsec-bouncer-register = {
    # Runs again on every crowdsec start, so a failed first start (hub download,
    # missing journal) does not leave the bouncer unregistered — which, failing
    # open, would go unnoticed.
    requires = [ "crowdsec.service" ];
    after = [ "crowdsec.service" ];
    partOf = [ "crowdsec.service" ];
    wantedBy = [ "crowdsec.service" ];
    before = [ "traefik.service" ];
    path = [ config.services.crowdsec.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = config.services.crowdsec.user;
      Group = config.services.crowdsec.group;
      LoadCredential = [ "key:${config.sops.secrets.crowdsec-bouncer-key.path}" ];
    };
    script = ''
      cscli bouncers delete traefik >/dev/null 2>&1 || true
      cscli bouncers add traefik --key "$(cat "$CREDENTIALS_DIRECTORY/key")" >/dev/null
    '';
  };

  networking.firewall.interfaces."ve-prometheus".allowedTCPPorts = [ 6060 ];

  # The module links its config files with tmpfiles, so the unit itself never
  # changes and a deploy would keep running the old parsers and acquisitions.
  systemd.services.crowdsec.restartTriggers = [
    (builtins.toJSON { inherit (config.services.crowdsec) settings hub; })
  ];
}
