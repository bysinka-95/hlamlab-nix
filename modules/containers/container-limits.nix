# Container resource limits (CPU, RAM, Disk I/O)
#
# This module adds systemd-based resource limits to containers
# WITHOUT requiring filesystem changes. Works with current ext4 setup.
#
# Usage: Import from modules/common/default.nix

{ ... }:
{
  # Resource limits for OpenCloud container
  systemd.services."container@opencloud" = {
    serviceConfig = {
      # CPU limits
      CPUQuota = "100%"; # Max 1 full CPU core (100% = 1 core, 200% = 2 cores)
      CPUWeight = 100; # CPU scheduling priority (1-10000, default 100)

      # Memory limits
      MemoryMax = "2G"; # Hard limit: 2GB
      MemoryHigh = "1.5G"; # Soft limit: starts throttling at 1.5GB

      # Disk I/O limits
      IOWeight = 100; # I/O scheduling priority (1-10000, default 100)
      # IOReadBandwidthMax = "/dev/sda 50M";  # Max 50MB/s read
      # IOWriteBandwidthMax = "/dev/sda 50M"; # Max 50MB/s write

      # Process limits
      TasksMax = 512; # Max 512 processes/threads

      # Network limits (if needed)
      # IPAddressDeny = "any";
      # IPAddressAllow = ["10.0.0.0/8" "localhost"];
    };
  };

  # Resource limits for Immich container
  systemd.services."container@immich" = {
    serviceConfig = {
      # CPU limits (Immich needs more for ML/transcoding)
      CPUQuota = "200%"; # Max 2 CPU cores
      CPUWeight = 200; # Higher priority than OpenCloud

      # Memory limits (Immich ML needs more RAM)
      MemoryMax = "4G"; # Hard limit: 4GB
      MemoryHigh = "3G"; # Soft limit: 3GB

      # Disk I/O limits (higher for media uploads)
      IOWeight = 200; # Higher I/O priority
      # IOReadBandwidthMax = "/dev/sda 100M";
      # IOWriteBandwidthMax = "/dev/sda 100M";

      # Process limits
      TasksMax = 1024; # More processes for ML workers
    };
  };

  # Template for future services
  # systemd.services."container@myservice" = {
  #   serviceConfig = {
  #     CPUQuota = "50%";
  #     MemoryMax = "1G";
  #     IOWeight = 50;
  #     TasksMax = 256;
  #   };
  # };
}

