{ config, ... }:
{
  # DNS mapping for host → container
  networking.hosts."10.0.0.5" = [ "authelia" ];

  # ZFS dataset for Authelia storage (SQLite database, configuration files, users file)
  disko.devices.zpool.tank.datasets."services/authelia" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/var/lib/services/authelia";
      quota = "10G";
      reservation = "1G";
      compression = "lz4";
      atime = "off";
    };
  };

  # Enable automated snapshots
  services.sanoid.datasets."tank/services/authelia" = {
    hourly = 24;
    daily = 7;
    weekly = 4;
    monthly = 12;
    autosnap = true;
    autoprune = true;
  };

  # Container Resource Limits
  systemd.services."container@authelia" = {
    serviceConfig = {
      CPUQuota = "100%";
      CPUWeight = 100;
      MemoryMax = "1G";
      MemoryHigh = "512M";
      MemorySwapMax = "0B";
      IOWeight = 100;
      TasksMax = 512;
    };
  };
}
