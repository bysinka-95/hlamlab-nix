# ZFS Storage Module

Declarative ZFS dataset management via Disko and disko-zfs.

- **Single source of truth**: all datasets in [
  `hosts/playground/disk-config.nix`](../../../hosts/playground/disk-config.nix)
- **Automatic management**: disko-zfs applies changes on every `nixos-rebuild switch` — no manual
  `zfs create`
- **Snapshots**: hourly/daily/weekly/monthly via sanoid
- **Compression**: lz4; **Integrity**: weekly scrubbing

---

## Quick Start

1. During installation, read host ID from the target machine (installer shell):

```bash
head -c 8 /etc/machine-id; echo
```

2. Set it in [`modules/common/zfs/default.nix`](./default.nix) **before first install**:

```nix
networking.hostId = "a1b2c3d4";
```

3. Install/deploy

```bash
nix run nixpkgs#nixos-rebuild -- switch --flake .#playground --target-host hlamnix@<ip> ...
```

Important: do not change `networking.hostId` after the initial install. If it changes later, `tank`
may fail to import during boot.

---

## Adding a Service Dataset

When adding a new service, its ZFS dataset and sanoid schedule are defined directly in its `host.nix` file (e.g. `modules/containers/<name>/host.nix`). The disko-zfs module will automatically pick them up during rebuild.

```nix
{ ... }:
{
  # ZFS Dataset
  disko.devices.zpool.tank.datasets."services/myservice" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/var/lib/services/myservice";
      quota = "100G";
      reservation = "20G";
      compression = "lz4";
      atime = "off";
    };
  };

  # Sanoid Snapshot Schedule
  services.sanoid.datasets."tank/services/myservice" = {
    hourly = 24; daily = 7; weekly = 4; monthly = 12;
    autosnap = true; autoprune = true;
  };
}
```

Deploy and verify: `zfs list tank/services/myservice`

---

## Current Datasets

See [main README](../../../README.md#zfs-datasets) for the full dataset table.

---

## Management Commands

```bash
# Overview
zfs list
zfs list -r tank/services
zfs list -o name,used,avail,quota,mountpoint

# Properties
zfs get quota,compressratio tank/services/immich

# Pool health
zpool status
zpool status -x   # errors only
sudo zpool scrub tank
```

---

## Snapshots

**Automatic schedule** (sanoid): 24 hourly · 7 daily · 4 weekly · 12 monthly

```bash
# List
zfs list -t snapshot -r tank/services/immich

# Manual snapshot + rollback
sudo zfs snapshot tank/services/immich@before-update
sudo zfs rollback tank/services/immich@before-update

# Browse snapshot files
ls /var/lib/services/immich/.zfs/snapshot/
```

---

## Backup / Replication

```bash
# Initial send
sudo zfs snapshot tank/services/immich@backup
sudo zfs send -R tank/services/immich@backup | ssh backup-server sudo zfs receive backup-tank/immich

# Incremental
sudo zfs snapshot tank/services/immich@backup-new
sudo zfs send -R -i @backup tank/services/immich@backup-new | ssh backup-server sudo zfs receive backup-tank/immich
```

For automated replication, add `services.syncoid` in `modules/common/zfs/default.nix`.

---

## Troubleshooting

**Dataset not mounting** — `sudo zfs mount tank/services/myservice`; check `zfs get mountpoint`.

**Pool not importing at boot (`tank/root` unavailable)** — verify `networking.hostId` was set before
first install and has not changed since.

**Quota exceeded** — increase `quota` in `disk-config.nix`, then `nixos-rebuild switch`.

**Snapshot space** — `zfs list -t snapshot -o name,used -s used`; destroy old ones with
`zfs destroy`.

**New dataset not created** — check syntax in `disk-config.nix`, verify disko-zfs in `flake.nix`,
check rebuild output.
