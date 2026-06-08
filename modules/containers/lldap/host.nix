{ ... }:
{
  networking.hosts."10.0.0.6" = [ "lldap" ];

  # ZFS Dataset
  disko.devices.zpool.tank.datasets."services/lldap" = {
    type = "zfs_fs";
    options = {
      mountpoint = "/var/lib/services/lldap";
      quota = "10G";
      reservation = "1G";
      compression = "lz4";
      atime = "off";
    };
  };

  # Snapshots
  services.sanoid.datasets."tank/services/lldap" = {
    hourly = 24;
    daily = 7;
    weekly = 4;
    monthly = 12;
    autosnap = true;
    autoprune = true;
  };

  # Limits
  systemd.services."container@lldap".serviceConfig = {
    CPUQuota = "100%";
    MemoryMax = "1G";
    MemoryHigh = "512M";
    IOWeight = 100;
    TasksMax = 512;
  };
}