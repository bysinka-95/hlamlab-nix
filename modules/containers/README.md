# Container Services

Each service is self-contained via a single `default.nix` module which defines the container, Traefik routing, ZFS datasets, and system users via the `hlamlab.services.<name>` submodule abstraction.

## Structure

```
modules/containers/
├── default.nix           # Imports all service definitions and the container frame
├── <service>/
│   └── default.nix       # Complete service definition using hlamlab.services.<name>
└── README.md
```

---

# Container Service Modules

All services run in native NixOS containers, isolated from the host.

## Service Anatomy

Each service resides in `modules/containers/<name>/default.nix` and leverages the `container-frame.nix` abstraction. This frame automatically handles ZFS datasets, Sanoid snapshots, systemd limits, DNS, Traefik routing, and users based on a simple set of attributes.

## Adding a Service

**Follow these 3 steps:**

### 1. Update `README.md`
Add the new service to the **Application Containers** table in the main [`README.md`](../../README.md). Assign an available IP and note the required storage quota.

### 2. Create the Module
In `modules/containers/<name>/`, create `default.nix`.

**`default.nix`** (App configuration):
```nix
{ config, ... }:
{
  hlamlab.services.myservice = {
    ip = "10.0.0.N"; # Check main README.md for next available IP
    port = 8080;
    domainPrefix = "myservice"; # Will map to https://myservice.yourdomain
    storageQuota = "10G";
    storageReservation = "1G";
    
    # Optional: override the service user (defaults to myservice)
    # serviceUser = "myservice";
    
    # Optional: Automatically manages sops.secrets inside the container
    secrets = {
      myservice-env = {
        key = "myservice/env";
        restartUnits = [ "myservice.service" ];
      };
    };
    
    # Storage bindings (ZFS datasets are automatically created and snapshotted)
    bindMounts = {
      "/var/lib/myservice" = {
        hostPath = "/var/lib/services/myservice";
        isReadOnly = false;
      };
    };

    # Container-specific NixOS config
    containerConfig = { lib, pkgs, config, ... }: {
      services.myservice = {
        enable = true;
        listenAddress = "0.0.0.0";
        environmentFile = config.sops.secrets.myservice-env.path;
      };
      
      systemd.services.myservice.serviceConfig.StateDirectory = "myservice";
      networking.firewall.allowedTCPPorts = [ 8080 ];
    };
  };

  # Make sure the host directory exists
  systemd.tmpfiles.rules = [ "d /var/lib/services/myservice 0750 root root -" ];
}
```

### 3. Register and Enable
Add `./myservice` to the imports list in [`modules/containers/default.nix`](default.nix).

To actually enable the service on a specific host, edit the host's configuration (e.g., `hosts/playground/configuration.nix`):
```nix
hlamlab.services.myservice.enable = true;
```

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

## Authelia Declarative Provisioning

Manage Authelia users, groups, and OAuth2 systems in `modules/containers/authelia/default.nix`. Changes are applied automatically on deploy.

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

Limits are defined directly in the service definition (`default.nix`).

```nix
  hlamlab.services.myservice = {
    # ...
    resourceLimits = {
      CPUQuota = "100%";
      MemoryMax = "2G";
      MemoryHigh = "1.5G";
      IOWeight = 100;
      TasksMax = 512;
    };
  };
```

**Sizing guide:** 
- Light (API/cache): 50% CPU, 512M RAM 
- Medium (web/db): 100%, 2G 
- Heavy (ML/media): 200%, 4G+

---

## Persistent Storage

Use `bindMounts` to map paths to `/var/lib/services/<name>` on the host. ZFS datasets and Sanoid backup schedules are automatically created by the container frame based on your `storageQuota` and `storageReservation` settings.

See [ZFS README](../common/zfs/README.md) for dataset creation and snapshot management.
