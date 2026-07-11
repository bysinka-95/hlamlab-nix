{ ... }:
{
  networking.hosts."10.0.0.8" = [ "searx" ];

  # ZFS Dataset
  disko.devices.zpool.tank.datasets."services/searx" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/var/lib/services/searx";
      quota = "10G";
      reservation = "1G";
      compression = "lz4";
      atime = "off";
    };
  };

  # Snapshots
  services.sanoid.datasets."tank/services/searx" = {
    hourly = 24;
    daily = 7;
    weekly = 4;
    monthly = 12;
    autosnap = true;
    autoprune = true;
  };

  # Limits
  systemd.services."container@searx".serviceConfig = {
    CPUQuota = "100%";
    MemoryMax = "1G";
    MemoryHigh = "512M";
    IOWeight = 100;
    TasksMax = 512;
  };
}
