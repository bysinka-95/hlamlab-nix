{ ... }:
{
  # Host-level log agent: captures the HOST journal (incl. the `container@<name>`
  # nspawn spawn wrappers) and Traefik's log files. It does NOT see the services
  # running INSIDE containers — nspawn keeps each container's journal private, so
  # the host reader only gets the spawn/boot wrapper, not immich-server.service &
  # co. Those real service logs are shipped by a per-container Alloy agent that
  # reads each container's own journal (see modules/containers/frame.nix,
  # hlamlab.observability.logAgent).
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
