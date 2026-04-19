# ZFS Configuration Module
#
# This module provides comprehensive ZFS support including:
# - Declarative dataset management via disko-zfs
# - Automatic snapshots via sanoid
# - ZFS scrubbing and monitoring
# - Shell aliases for common operations
#
# Structure:
#   README.md    - Comprehensive ZFS documentation
#
# Usage: Import this directory from configuration.nix

{ pkgs, ... }:
let
  vars = import ../local.nix;
in
{
  # Enable ZFS support
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  # Set ZFS host ID (required, must be unique per machine)
  # Generate with: head -c 8 /etc/machine-id
  networking.hostId = vars.hostId;

  # ZFS scrub (data integrity check) weekly
  services.zfs.autoScrub = {
    enable = true;
    interval = "weekly";
  };

  # Automatic snapshots using sanoid
  services.sanoid = {
    enable = true;

    datasets = {
      # OpenCloud snapshots
      "tank/services/opencloud" = {
        hourly = 24; # Keep 24 hourly snapshots
        daily = 7; # Keep 7 daily snapshots
        weekly = 4; # Keep 4 weekly snapshots
        monthly = 12; # Keep 12 monthly snapshots
        autosnap = true;
        autoprune = true;
      };

      # Immich snapshots
      "tank/services/immich" = {
        hourly = 24;
        daily = 7;
        weekly = 4;
        monthly = 12;
        autosnap = true;
        autoprune = true;
      };

      # Collabora snapshots
      "tank/services/collabora" = {
        hourly = 24;
        daily = 7;
        weekly = 4;
        monthly = 12;
        autosnap = true;
        autoprune = true;
      };

      # Authentik snapshots
      "tank/services/authentik" = {
        hourly = 24;
        daily = 7;
        weekly = 4;
        monthly = 12;
        autosnap = true;
        autoprune = true;
      };

      # Template for future services
      # "tank/services/myservice" = {
      #   hourly = 24;
      #   daily = 7;
      #   weekly = 4;
      #   monthly = 3;
      #   autosnap = true;
      #   autoprune = true;
      # };
    };
  };

  # Syncoid for replication (optional, for backing up to remote ZFS)
  # services.syncoid = {
  #   enable = true;
  #   commands = {
  #     "backup-opencloud" = {
  #       source = "tank/services/opencloud";
  #       target = "backup-server:backup-tank/opencloud";
  #       recursive = true;
  #     };
  #     "backup-immich" = {
  #       source = "tank/services/immich";
  #       target = "backup-server:backup-tank/immich";
  #       recursive = true;
  #     };
  #   };
  # };

  # ZFS monitoring and alerts
  services.zfs.zed = {
    enableMail = false; # Set to true and configure for email alerts
    settings = {
      ZED_DEBUG_LOG = "/var/log/zed.debug.log";
      ZED_EMAIL_ADDR = [ "root" ];
      ZED_EMAIL_PROG = "${pkgs.mailutils}/bin/mail";
      ZED_EMAIL_OPTS = "-s '@SUBJECT@' @ADDRESS@";

      # Email on pool errors
      ZED_NOTIFY_VERBOSE = true;
      ZED_NOTIFY_DATA = true;
    };
  };

  # Useful ZFS management aliases
  environment.shellAliases = {
    zfs-list = "zfs list -o name,used,avail,refer,quota,mountpoint";
    zfs-snapshots = "zfs list -t snapshot";
    zfs-usage = "zpool list -v";
  };
}
