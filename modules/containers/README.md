# Container Services

Each service is self-contained: container definition, Traefik routing, and DNS in its own directory.

## Structure

```
modules/containers/
├── default.nix           # NAT + imports all services
├── container-limits.nix  # systemd CPU/RAM/I/O limits per container
├── <service>/
│   ├── default.nix       # imports + DNS entry (networking.hosts)
│   ├── container.nix     # NixOS container definition
│   └── traefik.nix       # Traefik router + backend
└── README.md
```

---

## Adding a New Service

**All 6 steps are required.** Do step 1 first, before touching any Nix files.

### 1. Update `README.md § Current Services`

Add a row to the **Application Containers** table (IP, port, URL, storage path, CPU, RAM, ZFS quota/reservation) and
update the **ZFS Datasets** table. This is the single source of truth for service metadata.

### 2. Create `modules/containers/<name>/`

**`container.nix`** skeleton:

```nix
{ ... }:
let vars = import ../../common/local.nix; in
{
  containers.myservice = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.N";  # next available — check README.md
    bindMounts."/var/lib/myservice".hostPath = "/var/lib/services/myservice";
    config = { ... }: {
      services.myservice = { enable = true; listenAddress = "0.0.0.0"; };
      networking.firewall.allowedTCPPorts = [ <port> ];
      system.stateVersion = "26.05";
    };
  };
  systemd.tmpfiles.rules = [ "d /var/lib/services/myservice 0755 root root -" ];
}
```

**`traefik.nix`** skeleton:

```nix
{ ... }:
let vars = import ../../common/local.nix; in
{
  services.traefik.dynamicConfigOptions.http = {
    routers.myservice = {
      rule = "Host(`myservice.${vars.domain}`)";
      entryPoints = [ "https" ]; service = "myservice"; tls = {};
      middlewares = [ "security-headers" ];
    };
    services.myservice.loadBalancer.servers = [{ url = "http://myservice:<port>"; }];
  };
}
```

**`default.nix`**:

```nix
{ ... }: {
  imports = [ ./container.nix ./traefik.nix ];
  networking.hosts."10.0.0.N" = [ "myservice" ];
}
```

### 3. Register in parent

Add `./myservice` to the imports list in [`modules/containers/default.nix`](default.nix).

### 4. Add resource limits

Add to [`container-limits.nix`](container-limits.nix):

```nix
systemd.services."container@myservice".serviceConfig = {
  CPUQuota = "100%"; MemoryMax = "2G"; MemoryHigh = "1.5G"; IOWeight = 100; TasksMax = 512;
};
```

See [Resource Limits](#resource-limits) below for sizing guidance.

### 5. Add ZFS dataset

Add to [`hosts/playground/disk-config.nix`](../../hosts/playground/disk-config.nix) under
`disko.devices.zpool.tank.datasets`:

```nix
"services/myservice" = {
  type = "zfs_fs";
  options = {
    mountpoint = "/var/lib/services/myservice";
    quota = "100G"; reservation = "20G";
    compression = "lz4"; atime = "off";
    "com.sun:auto-snapshot" = "true";
  };
};
```

### 6. Add sanoid snapshot schedule

Add to `modules/common/zfs/default.nix` under `services.sanoid.datasets`:

```nix
"tank/services/myservice" = {
  hourly = 24; daily = 7; weekly = 4; monthly = 12;
  autosnap = true; autoprune = true;
};
```

---

## Current Services

See [main README](../../README.md#current-services) — IPs, ports, URLs, storage, resource limits, ZFS datasets.

---

## Container Management

```bash
machinectl list                                           # list containers
sudo nixos-container root-login <name>                    # shell into container
systemctl status container@<name>                         # status
sudo nixos-container run <name> -- journalctl -u <svc> -f # live logs
sudo nixos-container start/stop <name>
```

---

## Resource Limits

**File:** [`container-limits.nix`](container-limits.nix) — systemd-based CPU/RAM/I/O limits.

```bash
systemd-cgtop --order=memory                              # live usage
journalctl -u container@<name> | grep -i "memory\|limit"  # check if limits hit
```

**Temporary override:**

```bash
sudo systemctl set-property container@opencloud CPUQuota=200%
```

**Permanent** — edit `container-limits.nix`:

```nix
systemd.services."container@myservice".serviceConfig = {
  CPUQuota = "100%"; MemoryMax = "2G"; MemoryHigh = "1.5G"; IOWeight = 100; TasksMax = 512;
};
```

**Sizing guide:** Light (API/cache): 50% CPU, 512M RAM · Medium (web/db): 100%, 2G · Heavy (ML/media): 200%, 4G+

---

## Persistent Storage

Use bind mounts to `/var/lib/services/<name>` on the host (ZFS dataset). Data survives container rebuilds.

```nix
# container.nix
bindMounts."/var/lib/myservice" = { hostPath = "/var/lib/services/myservice"; isReadOnly = false; };
systemd.tmpfiles.rules = [ "d /var/lib/services/myservice 0755 root root -" ];
```

See [ZFS README](../common/zfs/README.md) for dataset creation and snapshot management.
