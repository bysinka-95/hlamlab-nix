# Host Configuration Guide

This document explains how to set up your hosts (like `hosts/playground/configuration.nix`), how to configure global environment settings, and how to declare, configure, and extend containerized services.

## 1. Global Settings (`hlamlab.settings`)

Global settings define the cluster-wide environment that your services and Traefik router rely on. These must be defined in your host's `configuration.nix`.

```nix
  hlamlab.settings = {
    # The base domain used for all Traefik routing (e.g. auth.yourdomain.com)
    domain = "yourdomain.com";
    
    # Your Cloudflare Tunnel ID (must match the credentials file in secrets)
    tunnelId = "00000000-0000-0000-0000-000000000000f";
    
    # ZFS host ID (obtain by running `head -c 8 /etc/machine-id`)
    hostId = "1a23bc45";

    # Optional: Customize the LDAP Base DN. 
    # If not set, it defaults to a domain-derived value (e.g. dc=yourdomain,dc=com)
    # ldapBaseDn = "dc=custom,dc=local";
  };
```

## 2. Enabling and Configuring Services

All services (like Authelia, Immich, OpenCloud) are disabled by default. You opt-in to running them on a specific host by enabling them in `hlamlab.services.<name>`.

### Basic Example

To simply enable a service with its default resource limits, IP address, and storage quotas:

```nix
  hlamlab.services = {
    authelia.enable = true;
    immich.enable = true;
  };
```

### Overriding Resource Limits & Networking

Every service comes with sensible default resource limits and network IP addresses. If you need to scale up a heavy service or change its IP to avoid conflicts on a new host, you can easily override any property:

```nix
  hlamlab.services.immich = {
    enable = true;
    
    # --- Networking ---
    # Assign a custom static IP for the container's virtual ethernet
    ip = "10.0.0.99";
    # By default, Immich might use "immich". This maps to https://photos.yourdomain.com
    domainPrefix = "photos"; 

    # --- Resource Limits ---
    # Give Immich more CPU and RAM for machine learning tasks
    cpuLimit = "400%";
    ramLimit = "8G";
    ramHigh = "6G";
    
    # --- Storage ---
    # Increase the ZFS dataset quota for photos
    storageQuota = "1T";
  };
```

## 3. Advanced Configuration

The container framework is designed to be highly extensible. You can inject custom NixOS configuration directly into the isolated container, map custom secrets, or alter Traefik routing.

### Using `extraContainerConfig`

`extraContainerConfig` allows you to inject arbitrary NixOS modules directly into the container. This is extremely useful if you need to install additional packages inside the container, configure a cron job, or tweak a systemd service without modifying the base service definition in `modules/containers/<name>.nix`.

```nix
  hlamlab.services.opencloud = {
    enable = true;
    
    extraContainerConfig = { pkgs, ... }: {
      # Install additional packages inside the OpenCloud container
      environment.systemPackages = [ pkgs.ffmpeg pkgs.imagemagick ];
      
      # Override the systemd service to increase the file descriptor limit
      systemd.services.opencloud.serviceConfig.LimitNOFILE = 1048576;
      
      # Add a custom hosts entry inside the container's /etc/hosts
      networking.extraHosts = "192.168.1.100 external-db.local";
    };
  };
```

### Managing Secrets

The `secrets` option simplifies `sops-nix` configuration. When a secret is declared here, the framework automatically maps the host's sops secret into the container, ensures it has the correct `0400` permissions, assigns ownership to the service user, and restarts the required systemd units when the secret changes.

*Note: You usually declare these inside the service definition (`modules/containers/<name>.nix`), but you can extend them from the host.*

```nix
  hlamlab.services.myservice = {
    enable = true;
    
    secrets = {
      # The attribute name is arbitrary, but conventionally represents the secret's purpose
      myservice-api-key = {
        # The key path in your secrets.yaml file
        key = "myservice/api-key";
        # The systemd units inside the container to restart when the secret changes
        restartUnits = [ "myservice-backend.service" ];
        # Optional: override the owner (defaults to the auto-created service user)
        # owner = "root";
      };
    };
  };
```

### Network and Traefik Overrides

If you need to bypass Traefik entirely, or want to map a container to multiple domain names, you can manipulate the `traefik` and `extraHosts` options.

```nix
  hlamlab.services.customapp = {
    enable = true;
    
    # Disable Traefik routing if you want to access the container via IP only,
    # or if you are using a different reverse proxy.
    traefik.enable = false;
    
    # Or, provide a highly custom Traefik rule (e.g., matching a specific path)
    traefik.rule = "Host(`custom.yourdomain.com`) && PathPrefix(`/api`)";
    
    # Provide custom Traefik middlewares
    traefikMiddlewares = [ "security-headers" "rate-limit" ];
    
    # Manage how the container is mapped in the HOST's /etc/hosts.
    # By default, the container is mapped to its name (e.g. "customapp").
    extraHosts = [ "customapp" "customapp-internal" "db-alias" ];
  };
```

## Complete Reference Table

Here is the complete list of options available under `hlamlab.services.<name>`:

| Option | Type | Default | Description |
|---|---|---|---|
| **Core** | | | |
| `enable` | `bool` | `false` | Enable the service on this host. |
| `autoStart` | `bool` | `true` | Automatically start the container on boot. |
| `privateNetwork`| `bool` | `true` | Enable a private network (virtual ethernet) for the container. |
| `stateVersion` | `str` | Host's `stateVersion`| The stateVersion for the container environment. |
| **Networking** | | | |
| `ip` | `str` | *Required* | Container local IP address (e.g., `10.0.0.5`). |
| `port` | `int` | *Required* | Container service port exposed to Traefik. |
| `domainPrefix` | `str` | `<name>` | Prefix for the domain routing (e.g., `'auth'`). |
| `nameservers` | `list` | `[]` | DNS nameservers for the container (e.g., `[ "1.1.1.1" ]`). |
| `extraHosts` | `list` | `[ "<name>" ]` | Hostnames mapped to the container's IP in the host's `/etc/hosts`. |
| `traefik.*` | `attrs` | *Enabled by default* | `enable` toggle and Traefik router `rule`. |
| `traefikMiddlewares`| `list` | `["security-headers"]` | Traefik middlewares applied to this service's router. |
| **Resources** | | | |
| `cpuLimit` | `str` | `"100%"` | Hard CPU limit (`CPUQuota`). |
| `cpuWeight` | `int` | `100` | CPU weight relative to other containers (`CPUWeight`). |
| `ramLimit` | `str` | `"1G"` | Hard RAM limit (`MemoryMax`). |
| `ramHigh` | `str` | `"512M"` | Soft RAM limit (`MemoryHigh`). |
| `memorySwapMax` | `str` | `"0B"` | Maximum swap usage (`MemorySwapMax`). |
| `ioWeight` | `int` | `100` | Block I/O weight (`IOWeight`). |
| `tasksMax` | `int` | `512` | Maximum number of processes/threads (`TasksMax`). |
| **Storage (ZFS)**| | | |
| `zfs.enable` | `bool` | `true` | Enable automatic ZFS dataset creation for this service. |
| `storageQuota` | `str` | `"10G"` | ZFS dataset maximum quota. |
| `storageReservation`| `str` | `"1G"` | ZFS dataset guaranteed reservation. |
| `sanoid.enable` | `bool` | `true` | Enable Sanoid automatic snapshots. |
| `bindMounts` | `attrs` | `{}` | Additional host-to-container path bind mounts. |
| **Advanced** | | | |
| `createServiceUser`| `bool` | `true` | Automatically create a system user/group. |
| `serviceUser` | `str` | `<name>` | Name of the auto-created service user. |
| `secrets` | `attrs` | `{}` | sops-nix secret mapping definitions. |
| `extraContainerConfig`| `module`| `{}` | Arbitrary NixOS configuration injected into the container. |
