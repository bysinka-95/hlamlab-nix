{ ... }:
{
  # DNS mapping for host → container
  networking.hosts."10.0.0.4" = [ "collabora" ];

  # ZFS Dataset
  disko.devices.zpool.tank.datasets."services/collabora" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/var/lib/services/collabora";
      quota = "20G";
      reservation = "5G";
      compression = "lz4";
      atime = "off";
    };
  };

  # Sanoid Snapshot Schedule
  services.sanoid.datasets."tank/services/collabora" = {
    hourly = 24;
    daily = 7;
    weekly = 4;
    monthly = 12;
    autosnap = true;
    autoprune = true;
  };

  # Container Resource Limits
  systemd.services."container@collabora" = {
    serviceConfig = {
      CPUQuota = "100%";
      CPUWeight = 120;
      MemoryMax = "1.5G";
      MemoryHigh = "1G";
      MemorySwapMax = "0B";
      IOWeight = 120;
      TasksMax = 512;
    };
  };
}