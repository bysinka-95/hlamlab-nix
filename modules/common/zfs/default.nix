{ config, ... }:
{
  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  networking.hostId = config.hlamlab.settings.hostId;

  # ZFS scrub (data integrity check) weekly
  services.zfs.autoScrub = {
    enable = true;
    interval = "weekly";
  };

  # Per-dataset snapshot schedules are declared by the container frame; see
  # modules/containers/frame.nix.
  services.sanoid.enable = true;

  # Pool events land in the journal, which Alloy ships to Loki. No mail relay
  # here, so no ZED_EMAIL_* — those need enableMail and an MTA to do anything.
  services.zfs.zed.enableMail = false;

  # Useful ZFS management aliases
  environment.shellAliases = {
    zfs-list = "zfs list -o name,used,avail,refer,quota,mountpoint";
    zfs-snapshots = "zfs list -t snapshot";
    zfs-usage = "zpool list -v";
  };
}
