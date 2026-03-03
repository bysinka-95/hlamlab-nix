# Container Services - Modular Structure

Each service is self-contained in its own directory with container definition, Traefik routing, and DNS configuration.

## Structure

```
modules/containers/
├── default.nix           # NAT + imports all services
├── container-limits.nix  # Optional: CPU/RAM/I/O resource limits
├── service-a/            # Example: Self-contained service module
│   ├── default.nix       # Imports container + traefik + DNS
│   ├── container.nix     # NixOS container
│   └── traefik.nix       # Traefik routing
└── README.md
```

## Container Resource Limits

**File:** `container-limits.nix`

This optional module adds systemd-based resource limits to prevent containers from consuming excessive CPU, RAM, or I/O
resources.

### Features

- **CPU limits**: Restrict cores/percentage per container
- **Memory limits**: Hard and soft memory caps
- **I/O limits**: Control disk read/write priorities
- **Process limits**: Max number of processes/threads

### Current Configuration

**OpenCloud:**

- CPU: 1 core max (100%)
- RAM: 2GB hard limit, 1.5GB soft limit
- I/O: Standard priority
- Processes: 512 max

**Immich:**

- CPU: 2 cores max (200%)
- RAM: 4GB hard limit, 3GB soft limit
- I/O: High priority (for media uploads)
- Processes: 1024 max

### Monitoring Resource Usage

```bash
# Live resource monitor (shows all containers)
systemd-cgtop

# Sort by CPU
systemd-cgtop --order=cpu

# Sort by memory
systemd-cgtop --order=memory

# Check specific container status
systemctl status container@opencloud

# Check if limits are being hit
journalctl -u container@immich | grep -i "memory\|cpu\|limit"
```

### Adjusting Limits

**Temporary adjustment (until reboot):**

```bash
sudo systemctl set-property container@opencloud CPUQuota=200%
sudo systemctl set-property container@immich MemoryMax=8G
```

**Permanent adjustment:**

Edit `modules/containers/container-limits.nix`:

```nix
systemd.services."container@myservice" = {
  serviceConfig = {
    CPUQuota = "150%";      # 1.5 CPU cores
    MemoryMax = "3G";       # 3GB hard limit
    MemoryHigh = "2.5G";    # 2.5GB soft limit (starts throttling)
    IOWeight = 150;         # I/O priority (1-10000)
    TasksMax = 768;         # Max processes
  };
};
```

Then rebuild to apply permanently.

### Adding Limits for New Services

When adding a new service, also add its limits in `container-limits.nix`:

```nix
systemd.services."container@myservice" = {
  serviceConfig = {
    CPUQuota = "50%";       # Half a core
    MemoryMax = "1G";       # 1GB max
    IOWeight = 100;         # Standard priority
    TasksMax = 256;         # Light service
  };
};
```

### Resource Limit Examples

**Light service (cache, simple API):**

```nix
CPUQuota = "50%";          # Half core
MemoryMax = "512M";        # 512MB
IOWeight = 50;             # Low priority
TasksMax = 256;
```

**Medium service (web app, database):**

```nix
CPUQuota = "100%";         # 1 core
MemoryMax = "2G";          # 2GB
IOWeight = 100;            # Normal priority
TasksMax = 512;
```

**Heavy service (ML, media processing):**

```nix
CPUQuota = "200%";         # 2 cores
MemoryMax = "4G";          # 4GB
IOWeight = 200;            # High priority
TasksMax = 1024;
```

## Current Services

| Service   | IP        | Port | URL                        | Storage                              |
|-----------|-----------|------|----------------------------|--------------------------------------|
| opencloud | 10.0.0.2  | 9200 | opencloud.yourdomain       | `/var/lib/services/opencloud` (host) |
| immich    | 10.0.0.3  | 2283 | immich.yourdomain          | `/var/lib/services/immich` (host)    |
| -         | 10.0.0.4+ | -    | Available for new services | -                                    |

## Adding a New Service

1. **Create directory**: `mkdir -p modules/containers/myservice`

2. **Create `container.nix`**:

```nix
{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  containers.myservice = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.0.0.1";
    localAddress = "10.0.0.4";  # Next available IP
    
    config = { pkgs, ... }: {
      services.myservice.enable = true;
      networking.firewall.allowedTCPPorts = [ 8080 ];
      system.stateVersion = "26.05";
    };
  };
}
```

3. **Create `traefik.nix`**:

```nix
{ ... }:
let
  vars = import ../../common/local.nix;
in
{
  services.traefik.dynamicConfigOptions = {
    http = {
      routers.myservice = {
        rule = "Host(`myservice.${vars.domain}`)";
        entryPoints = [ "https" ];
        service = "myservice";
        tls = {};
      };
      services.myservice.loadBalancer.servers = [
        { url = "http://myservice:8080"; }
      ];
    };
  };
}
```

4. **Create `default.nix`**:

```nix
{ ... }:
{
  imports = [ ./container.nix ./traefik.nix ];
  networking.hosts."10.0.0.4" = [ "myservice" ];
}
```

5. **Import in `modules/containers/default.nix`**:

```nix
imports = [
  ./service-a
  ./service-b
  ./myservice  # Add this
];
```

6. **Deploy**

## Container Management

```bash
# List containers
machinectl list

# Login to container
sudo nixos-container root-login <name>

# Check status
systemctl status container@<name>

# View logs
sudo nixos-container run <name> -- journalctl -u <service> -f

# Start/stop
sudo nixos-container start/stop <name>
```

## External Storage (Persistent Data)

For stateful services (databases, media storage), use **bind mounts** to store data on the host filesystem:

**Benefits:**

- Data survives container recreation/updates
- Easy to backup from host
- Can use host storage features (RAID, ZFS, etc.)
- Simple to replicate to other machines

**Example**:

```nix
containers.myservice = {
  # ...
  bindMounts = {
    "/var/lib/mydata" = {
      hostPath = "/var/lib/services/mydata";  # Host directory under services/
      isReadOnly = false;
    };
  };
};

# Create host directory with proper permissions
systemd.tmpfiles.rules = [
  "d /var/lib/services 0755 root root -"
  "d /var/lib/services/mydata 0755 root root -"
];
```

**Backup Strategy:**

- Host directories under `/var/lib/services/` are easy to snapshot (rsync, ZFS snapshots, etc.)
- Container state is ephemeral; persistent data lives on host
- Can mount network storage (NFS, CIFS) for redundancy

## IP Allocation

- 10.0.0.1 - Host gateway (reserved)
- 10.0.0.2 - opencloud
- 10.0.0.3 - immich
- 10.0.0.4+ - Available for new services

## Best Practices

1. Use folder imports (`./servicename`)
2. Keep everything self-contained in service directory
3. Use `../../common/local.nix` for domain variable
4. Services must bind to `0.0.0.0` to be accessible
5. Update IP allocation table when adding services
6. Use bind mounts for persistent data (see External Storage section above)
7. Consider ZFS datasets and resource limits for production

## Advanced Topics

### Storage Isolation & Resource Limits

**In this directory:**

- **[container-limits.nix](./container-limits.nix)** - CPU/RAM/I/O limits (see section above)

**See also:**

- **ZFS Datasets**: Per-service disk quotas, compression, snapshots, replication
    - See: [modules/common/zfs/README.md](../common/zfs/README.md)

## Related Documentation

- [Main README](../../README.md)
- [Network README](../common/network/README.md)
- [Secrets README](../secrets/README.md)
