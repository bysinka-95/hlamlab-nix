# Container Services - Modular Structure

Each service is self-contained in its own directory with container definition, Traefik routing, and DNS configuration.

## Structure

```
modules/containers/
├── default.nix        # NAT + imports all services
├── service-a/         # Example: Self-contained service module
│   ├── default.nix    # Imports container + traefik + DNS
│   ├── container.nix  # NixOS container
│   └── traefik.nix    # Traefik routing
└── README.md
```

## Example: Current Services

| Service   | IP        | Port | URL                        | Storage                     |
|-----------|-----------|------|----------------------------|-----------------------------|
| opencloud | 10.0.0.2  | 9200 | opencloud.yourdomain       | `/var/lib/opencloud` (host) |
| immich    | 10.0.0.3  | 2283 | immich.yourdomain          | `/var/lib/immich` (host)    |
| -         | 10.0.0.4+ | -    | Available for new services | -                           |

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

**Example** (from Immich):

```nix
containers.myservice = {
  # ...
  bindMounts = {
    "/var/lib/mydata" = {
      hostPath = "/var/lib/mydata";  # Host directory
      isReadOnly = false;
    };
  };
};

# Create host directory with proper permissions
systemd.tmpfiles.rules = [
  "d /var/lib/mydata 0750 <uid> <gid> -"
];
```

**Backup Strategy:**

- Host directories under `/var/lib/` are easy to snapshot (rsync, ZFS snapshots, etc.)
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

## Related Documentation

- [Main README](../../README.md)
- [Network README](../common/network/README.md)
- [Secrets README](../../modules/secrets/README.md)

