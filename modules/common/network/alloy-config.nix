# Alloy river config, shared by the host agent (modules/common/network/alloy.nix)
# and by the per-container agent the frame injects (modules/containers/frame.nix).
# Both read a systemd journal and push it to Loki; only the labels and any extra
# scrape blocks differ.
{ lokiUrl, labels, extra ? "" }: ''
  loki.write "default" {
    endpoint {
      url = "${lokiUrl}"
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
    labels        = { ${labels} }
    forward_to    = [loki.write.default.receiver]
  }
'' + extra
