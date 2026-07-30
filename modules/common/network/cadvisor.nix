{ config, lib, ... }:
lib.mkIf config.hlamlab.observability.enable {
  # True per-container resource metrics. node_exporter inside each container reads
  # the shared host /proc, so it reports host-global mem/cpu/disk (identical for
  # every container). cAdvisor reads the host cgroup tree instead, where systemd
  # accounts each `container@<name>.service` separately — giving real per-container
  # CPU / memory / network / IO. One instance on the host covers every container.
  #
  # Bound to 0.0.0.0 and firewalled open so the prometheus container scrapes it at
  # the gateway address 10.0.0.1:8080 (same pattern as traefik :8082 / cloudflared
  # :60123 metrics). cloudflared forwards none of these, so they stay LAN-internal.
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

  networking.firewall.allowedTCPPorts = [ 8080 ];
}
