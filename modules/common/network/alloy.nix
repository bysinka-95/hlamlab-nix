{ ... }:
{
  # Single host-level log agent. NixOS containers are systemd-nspawn, which links
  # each container journal into the host's /var/log/journal/<machine-id>/, so one
  # journal reader here captures every container + the host. Traefik is the only
  # file-based logger and runs host-side, so we tail its files directly. No
  # per-container agent needed.
  services.alloy.enable = true;

  # Read the journal (systemd-journal group) and Traefik's log files.
  systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "systemd-journal" "traefik" ];

  environment.etc."alloy/config.alloy".text = ''
    loki.write "default" {
      endpoint {
        url = "http://10.0.0.11:3100/loki/api/v1/push"
      }
    }

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal__hostname"]
        target_label  = "host"
      }
      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "level"
      }
    }

    loki.source.journal "read" {
      path          = "/var/log/journal"
      max_age       = "12h"
      relabel_rules = loki.relabel.journal.rules
      labels        = { job = "systemd-journal" }
      forward_to    = [loki.write.default.receiver]
    }

    local.file_match "traefik" {
      path_targets = [{ __path__ = "/var/log/traefik/*.log", job = "traefik" }]
    }

    loki.source.file "traefik" {
      targets    = local.file_match.traefik.targets
      forward_to = [loki.write.default.receiver]
    }
  '';
}
