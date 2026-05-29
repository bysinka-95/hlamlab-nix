{ ... }:
{
  # DNS mapping for host → container
  networking.hosts."10.0.0.5" = [ "kanidm" ];

  # ZFS Dataset
  disko.devices.zpool.tank.datasets."services/kanidm" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/var/lib/services/kanidm";
      quota = "10G";
      reservation = "1G";
      compression = "lz4";
      atime = "off";
    };
  };

  # Sanoid Snapshot Schedule
  services.sanoid.datasets."tank/services/kanidm" = {
    hourly = 24;
    daily = 7;
    weekly = 4;
    monthly = 12;
    autosnap = true;
    autoprune = true;
  };

  # Container Resource Limits
  systemd.services."container@kanidm" = {
    serviceConfig = {
      CPUQuota = "100%";
      CPUWeight = 150;
      MemoryMax = "1G";
      MemoryHigh = "512M";
      MemorySwapMax = "0B";
      IOWeight = 150;
      TasksMax = 512;
    };
  };
}