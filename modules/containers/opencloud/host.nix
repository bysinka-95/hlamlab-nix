{ ... }:
{
  # DNS mapping for host → container
  networking.hosts."10.0.0.2" = [ "opencloud" ];

  # ZFS Dataset
  disko.devices.zpool.tank.datasets."services/opencloud" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/var/lib/services/opencloud";
      quota = "50G";
      reservation = "10G";
      compression = "lz4";
      atime = "off";
    };
  };

  # Sanoid Snapshot Schedule
  services.sanoid.datasets."tank/services/opencloud" = {
    hourly = 24;
    daily = 7;
    weekly = 4;
    monthly = 12;
    autosnap = true;
    autoprune = true;
  };

  # Container Resource Limits
  systemd.services."container@opencloud" = {
    serviceConfig = {
      CPUQuota = "100%";
      CPUWeight = 100;
      MemoryMax = "2G";
      MemoryHigh = "1.5G";
      MemorySwapMax = "0B";
      IOWeight = 100;
      TasksMax = 512;
    };
  };
}