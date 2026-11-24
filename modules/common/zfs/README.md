# ZFS storage module

Disko and disko-zfs manage the ZFS datasets from the configuration.

- **Dataset declarations**: the base datasets (`root`, `nix`, `home`, `services`,
  `backups`) are in [`hosts/playground/disk-config.nix`](../../../hosts/playground/disk-config.nix).
  `modules/containers/frame.nix` adds one dataset for each enabled service.
- **No manual `zfs create`**: disko-zfs applies the datasets and their properties at each deploy.
- **Snapshots**: Sanoid takes hourly, daily, weekly and monthly snapshots.
- **Compression**: lz4. **Integrity**: a scrub each week.
- **Service datasets** have `setuid=off` (see the
  [container README](../../containers/README.md#persistent-storage)).

---

## Quick start

1. During the install, read the host ID on the target (installer shell):

```bash
head -c 8 /etc/machine-id; echo
```

2. Set it in [`hosts/playground/configuration.nix`](../../../hosts/playground/configuration.nix)
   **before the first install**:

```nix
hlamlab.settings.hostId = "a1b2c3d4";
```

3. Install, then deploy:

```bash
nix run nixpkgs#deploy-rs -- .#playground
```

Do not change `networking.hostId` after the install. With a different host ID, `tank` can fail to
import at boot.

---

## Dataset for a new service

The frame creates the dataset and the Sanoid schedule for each service in
`hlamlab.services.<name>`. Set the size in the service module (`modules/containers/<name>.nix`)
or override it from the host:

```nix
{ ... }:
{
  hlamlab.services.myservice = {
    storageQuota = "100G";
    storageReservation = "20G";

    # zfs.enable = false;   # no dataset, no snapshots, no dataDir mount
  };
}
```

Deploy, then check: `zfs list tank/services/myservice`

---

## Current datasets

The [main README](../../../README.md#zfs-datasets) has the full dataset table.

---

## Management commands

```bash
# Overview
zfs list
zfs list -r tank/services
zfs list -o name,used,avail,quota,mountpoint

# Properties
zfs get quota,compressratio,setuid tank/services/immich

# Pool health
zpool status
zpool status -x   # errors only
sudo zpool scrub tank
```

---

## Snapshots

**Automatic schedule** (Sanoid): 24 hourly, 7 daily, 4 weekly, 12 monthly.

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

## Backup and replication

```bash
# Initial send
sudo zfs snapshot tank/services/immich@backup
sudo zfs send -R tank/services/immich@backup | ssh backup-server sudo zfs receive backup-tank/immich

# Incremental
sudo zfs snapshot tank/services/immich@backup-new
sudo zfs send -R -i @backup tank/services/immich@backup-new | ssh backup-server sudo zfs receive backup-tank/immich
```

For automatic replication, add `services.syncoid` in `modules/common/zfs/default.nix`.

---

## Troubleshooting

**A dataset does not mount.** Run `sudo zfs mount tank/services/myservice`. Check
`zfs get mountpoint`.

**The pool does not import at boot (`tank/root` unavailable).** Check that you set
`networking.hostId` before the first install and did not change it since.

**The quota is full.** Increase `storageQuota` in the service module, then deploy.

**Snapshots use too much space.** List them with `zfs list -t snapshot -o name,used -s used`.
Delete old ones with `zfs destroy`.

**A new dataset is missing.** Check the service has `enable = true` and `zfs.enable = true`. For a
base dataset, check `disk-config.nix`. Read the deploy output for disko-zfs errors.
