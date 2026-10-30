{ config, ... }:
{
  # Host-level log agent: captures the HOST journal (incl. the `container@<name>`
  # nspawn spawn wrappers) and Traefik's log files. It does NOT see the services
  # running INSIDE containers — nspawn keeps each container's journal private, so
  # the host reader only gets the spawn/boot wrapper, not immich-server.service &
  # co. Those real service logs are shipped by a per-container Alloy agent that
  # reads each container's own journal (see modules/containers/frame.nix) and
  # pushes to the receiver below — never to Loki itself, so no container can
  # reach Loki and read other services' logs.
  services.alloy.enable = true;

  # The containers' push receiver (:3500, also in frame.nix), open to them only.
  networking.firewall.extraInputRules = ''
    iifname "ve-*" tcp dport 3500 accept
  '';

  # Read the journal (systemd-journal group) and Traefik's log files.
  systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "systemd-journal" "traefik" ];

  environment.etc."alloy/config.alloy".text = import ./alloy-config.nix {
    lokiUrl = "http://${config.hlamlab.services.loki.address}/loki/api/v1/push";
    labels = ''job = "systemd-journal"'';
    extra = ''

      local.file_match "traefik" {
        path_targets = [{ __path__ = "/var/log/traefik/*.log", job = "traefik" }]
      }

      loki.source.file "traefik" {
        targets    = local.file_match.traefik.targets
        forward_to = [loki.write.default.receiver]
      }

      // Pushes from the per-container agents; their labels are kept.
      loki.source.api "containers" {
        http {
          listen_address = "0.0.0.0"
          listen_port    = 3500
        }
        forward_to = [loki.write.default.receiver]
      }
    '';
  };
}
