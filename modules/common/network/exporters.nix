{ config, lib, ... }:
lib.mkIf config.hlamlab.observability.enable {
  # Machine-level metrics: CPU, memory, load, disk I/O. There is exactly one
  # kernel here — nspawn shares /proc and /sys — so this is the only place those
  # are worth collecting. The per-container node_exporters that frame.nix injects
  # deliberately run with --collector.disable-defaults and do NOT duplicate them;
  # they cover the namespaced collectors (systemd units, mount namespace,
  # netns) that this exporter structurally cannot see.
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";
    enabledCollectors = [ "systemd" ];
  };

  # Per-container resource usage, which node_exporter structurally cannot give:
  # cAdvisor reads the host cgroup tree, where systemd accounts each
  # `container@<name>.service` separately — real per-container CPU / memory /
  # network / IO.
  services.cadvisor = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 8080;
    # Trim cgroup noise: keep cpu/memory/network/diskIO, drop the heavy/unused
    # collectors so the exporter stays light on a homelab host.
    extraOptions = [
      "--enable_metrics=cpu,memory,network,diskIO,oom_event,process"
      "--store_container_labels=false"
    ];
  };

  # Both bound to 0.0.0.0 and firewalled open so the prometheus container scrapes
  # them at the gateway address (same pattern as traefik :8082 / cloudflared
  # :60123). cloudflared forwards none of these, so they stay LAN-internal.
  # Containers' own exporters listen on :9101 and open their own firewall.
  networking.firewall.allowedTCPPorts = [ 8080 9100 ];
}
