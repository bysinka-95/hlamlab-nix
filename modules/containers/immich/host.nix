{ ... }:
{
  # DNS mapping for host → container
  networking.hosts."10.0.0.3" = [ "immich" ];

  # ZFS Dataset
  disko.devices.zpool.tank.datasets."services/immich" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/var/lib/services/immich";
      quota = "300G";
      reservation = "10G";
      compression = "lz4";
      atime = "off";
    };
  };

  # Sanoid Snapshot Schedule
  services.sanoid.datasets."tank/services/immich" = {
    hourly = 24;
    daily = 7;
    weekly = 4;
    monthly = 12;
    autosnap = true;
    autoprune = true;
  };

  # Container Resource Limits
  systemd.services."container@immich" = {
    serviceConfig = {
      CPUQuota = "200%";
      CPUWeight = 200;
      MemoryMax = "4G";
      MemoryHigh = "3G";
      MemorySwapMax = "0B";
      IOWeight = 200;
      TasksMax = 1024;
    };
  };
}