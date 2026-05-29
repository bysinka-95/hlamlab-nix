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

# Container Service Modules

All services run in native NixOS containers, isolated from the host.

## Service Anatomy

Each service resides in `modules/containers/<name>/` and consists of 4 files:

| File | Responsibility |
| :--- | :--- |
| `container.nix` | Container definition: `autoStart`, `privateNetwork`, bind mounts, `config` block. |
| `traefik.nix` | Traefik reverse proxy routing: `routers`, `services` (dynamic config). |
| `host.nix` | Host-level integrations: DNS, ZFS dataset, sanoid schedule, resource limits. |
| `default.nix` | Module imports (glues the 3 files above together). |

## Adding a Service

**Follow these 3 steps:**

### 1. Update `README.md`
Add the new service to the **Application Containers** table in the main [`README.md`](../../README.md). Assign an available IP.

### 2. Create the Module
In `modules/containers/<name>/`, create the 4 required files (skeletons provided in code blocks below).

**`container.nix`** (App configuration):
```nix
{ ... }:
let vars = import ../../common/local.nix; in
{
  containers.myservice = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.N"; # Check main README.md
    bindMounts."/var/lib/myservice".hostPath = "/var/lib/services/myservice";
    config = { ... }: {
      services.myservice = { enable = true; listenAddress = "0.0.0.0"; };
      networking.firewall.allowedTCPPorts = [ <port> ];
      system.stateVersion = "25.11";
    };
  };
  systemd.tmpfiles.rules = [ "d /var/lib/services/myservice 0755 root root -" ];
}
```

**`traefik.nix`** (Reverse proxy):
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

**`host.nix`** (Host integration):
```nix
{ ... }:
{
  networking.hosts."10.0.0.N" = [ "myservice" ];

  # ZFS Dataset
  disko.devices.zpool.tank.datasets."services/myservice" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/var/lib/services/myservice";
      quota = "50G"; reservation = "10G"; compression = "lz4"; atime = "off";
    };
  };

  # Snapshots
  services.sanoid.datasets."tank/services/myservice" = {
    hourly = 24; daily = 7; weekly = 4; monthly = 12;
    autosnap = true; autoprune = true;
  };

  # Limits
  systemd.services."container@myservice".serviceConfig = {
    CPUQuota = "100%"; MemoryMax = "2G"; MemoryHigh = "1.5G"; IOWeight = 100; TasksMax = 512;
  };
}
```

**`default.nix`** (Import):
```nix
{ ... }: { imports = [ ./container.nix ./traefik.nix ./host.nix ]; }
```

### 3. Register
Add `./myservice` to the imports list in [`modules/containers/default.nix`](default.nix).

---

## Container Operations

```bash
machinectl list                                           # list containers
sudo nixos-container root-login <name>                    # shell into container
systemctl status container@<name>                         # status
sudo nixos-container run <name> -- journalctl -u <svc> -f # live logs
```

---

## Current Services

See [main README](../../README.md#current-services) — IPs, ports, URLs, storage, resource limits, ZFS datasets.

## Kanidm Declarative Provisioning

Manage Kanidm users, groups, and OAuth2 systems in `modules/containers/kanidm/container.nix` under the `services.kanidm.provision` block. Changes are applied automatically on deploy.

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
