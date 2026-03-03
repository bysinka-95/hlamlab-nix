# ZFS Storage Module

Declarative ZFS dataset management via Disko and disko-zfs.

## Overview

**ZFS is the only supported filesystem** with automatic, declarative dataset management:

- **Single source of truth**: All datasets in `hosts/playground/disk-config.nix`
- **Automatic management**: disko-zfs detects and manages Disko's ZFS declarations
- **No manual commands**: Edit config → `nixos-rebuild switch` → done!
- **Snapshots**: Automatic hourly/daily/weekly/monthly via sanoid
- **Compression**: lz4 compression (30-50% space savings)
- **Data integrity**: Weekly scrubbing

---

## Quick Start

### 1. Install System

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake '.#playground' \
  --target-host nixos@<ip>
```

Creates: ZFS pool, base datasets, service datasets (opencloud, immich)

### 2. Set Host ID

```bash
ssh hlamnix@<ip> "head -c 8 /etc/machine-id"
# Output: a1b2c3d4
```

Edit `modules/common/zfs/default.nix`:

```nix
networking.hostId = "a1b2c3d4";
```

### 3. Deploy

```bash
nixos-rebuild switch --flake .#playground ...
```

---

## Adding a Service Dataset

**Edit:** `hosts/playground/disk-config.nix`

```nix
"services/myservice" = {
  type = "zfs_fs";
  options = {
    mountpoint = "/var/lib/services/myservice";
    quota = "100G";
    reservation = "20G";
    compression = "lz4";
    atime = "off";
    "com.sun:auto-snapshot" = "true";
  };
};
```

**Deploy:**

```bash
nixos-rebuild switch --flake .#playground ...
```

**Verify:**

```bash
zfs list tank/services/myservice
```

---

## Updating Properties

Edit quota/compression in `disk-config.nix`:

```nix
quota = "500G";  # Changed from 300G
```

Deploy:

```bash
nixos-rebuild switch
```

disko-zfs applies changes automatically!

---

## Current Datasets

| Dataset                 | Mount                       | Quota | Reservation | Compression |
|-------------------------|-----------------------------|-------|-------------|-------------|
| tank/root               | /                           | -     | -           | lz4         |
| tank/nix                | /nix                        | -     | -           | lz4         |
| tank/home               | /home                       | -     | -           | lz4         |
| tank/services           | /var/lib/services           | -     | -           | lz4         |
| tank/services/opencloud | /var/lib/services/opencloud | 50G   | 10G         | lz4         |
| tank/services/immich    | /var/lib/services/immich    | 300G  | 50G         | lz4         |
| tank/backups            | /var/backups                | -     | -           | gzip        |

---

## Management Commands

### Viewing

```bash
zfs list                        # All datasets
zfs list -r tank/services       # Service datasets only
zfs list -o name,used,avail,refer,quota,mountpoint
```

### Properties

```bash
zfs get all tank/services/immich
zfs get quota tank/services/opencloud
zfs get compressratio tank/services/immich
```

### Pool Health

```bash
zpool status                    # Pool status
zpool status -x                 # Errors only
zpool list -v                   # Detailed info
```

### Scrubbing

```bash
sudo zpool scrub tank           # Manual scrub
zpool status tank               # Check progress
```

---

## Snapshots

### Automatic Schedule

Via sanoid (configured in `modules/common/zfs/default.nix`):

- Hourly: 24 snapshots (1 day)
- Daily: 7 snapshots (1 week)
- Weekly: 4 snapshots (1 month)
- Monthly: 12 snapshots (1 year)

### Operations

```bash
zfs list -t snapshot                           # List all
zfs list -t snapshot -r tank/services/immich   # Specific dataset
sudo zfs snapshot tank/services/immich@before-update
sudo zfs rollback tank/services/immich@before-update
sudo zfs destroy tank/services/immich@old-snapshot
```

### Restore Files

```bash
ls /var/lib/services/immich/.zfs/snapshot/
sudo cp /var/lib/services/immich/.zfs/snapshot/autosnap_2026-03-03_12:00:00_hourly/photo.jpg \
        /var/lib/services/immich/photo.jpg
```

### Add Schedule for New Service

Edit `modules/common/zfs/default.nix`:

```nix
services.sanoid.datasets."tank/services/myservice" = {
  hourly = 24;
  daily = 7;
  weekly = 4;
  monthly = 12;
  autosnap = true;
  autoprune = true;
};
```

---

## Backup & Replication

### Manual Backup

```bash
# Initial
sudo zfs snapshot tank/services/immich@backup
sudo zfs send -R tank/services/immich@backup | \
  ssh backup-server sudo zfs receive backup-tank/immich

# Incremental
sudo zfs snapshot tank/services/immich@backup-new
sudo zfs send -R -i @backup tank/services/immich@backup-new | \
  ssh backup-server sudo zfs receive backup-tank/immich
```

### Automated (Optional)

Edit `modules/common/zfs/default.nix`:

```nix
services.syncoid = {
  enable = true;
  commands."backup-opencloud" = {
    source = "tank/services/opencloud";
    target = "backup-server:backup-tank/opencloud";
    recursive = true;
  };
};
```

---

## How It Works

### disko-zfs Integration

1. **During install** (nixos-anywhere):
    - Disko creates all datasets from disk-config.nix
    - Includes system + service datasets

2. **After install** (nixos-rebuild):
    - disko-zfs detects Disko's ZFS pool
    - Manages datasets declared in disk-config.nix
    - Creates new datasets, updates properties

### Single Source of Truth

**Everything in:** `hosts/playground/disk-config.nix`

- System datasets (/, /nix, /home)
- Service datasets (opencloud, immich, etc.)
- All properties (quotas, compression, snapshots)

**Result:**

- One file for all datasets
- Works during install AND runtime
- No duplication
- Fully declarative

---

## Architecture

```
tank/                                    # ZFS pool
├── root → /
├── nix → /nix
├── home → /home
├── services → /var/lib/services
│   ├── opencloud → /var/lib/services/opencloud
│   └── immich → /var/lib/services/immich
└── backups → /var/backups
```

### Container Integration

```nix
containers.myservice = {
  bindMounts."/var/lib/myservice" = {
    hostPath = "/var/lib/services/myservice";  # ZFS dataset
    isReadOnly = false;
  };
};
```

---

## Best Practices

1. **Always use compression**: `compression = "lz4";`
2. **Set appropriate quotas**: Caches (20-50GB), Databases (100-200GB), Media (500GB-2TB)
3. **Reserve space**: `reservation = "20G";` for critical services
4. **Enable snapshots**: `"com.sun:auto-snapshot" = "true";`
5. **Disable atime**: `atime = "off";` for performance
6. **Snapshot before changes**: `sudo zfs snapshot tank/services/myservice@before-update`
7. **Monitor compression**: `zfs get compressratio -r tank/services`
8. **Test rollbacks**: Practice in dev environment

---

## Troubleshooting

### Dataset Not Mounting

```bash
zfs list tank/services/myservice
zfs get mountpoint tank/services/myservice
sudo zfs mount tank/services/myservice
```

### Quota Exceeded

```bash
zfs list tank/services/myservice
# Edit disk-config.nix: quota = "200G";
nixos-rebuild switch
```

### Snapshot Space Issues

```bash
zfs list -t snapshot -o name,used -s used
sudo zfs destroy tank/services/myservice@old-snapshot
```

### New Dataset Not Created

1. Check syntax in disk-config.nix
2. Verify disko-zfs in flake.nix
3. Check rebuild output
4. Verify pool: `zpool list`

---

## Shell Aliases

Pre-configured:

```bash
zfs-list        # Dataset overview
zfs-snapshots   # List snapshots
zfs-usage       # Pool usage
```

---

## Related Documentation

- [Container Management](../../containers/README.md)
- [Main README](../../../README.md)
