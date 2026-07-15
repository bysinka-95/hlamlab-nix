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

{ config, pkgs, ... }:
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

  # Automatic snapshots using sanoid
  services.sanoid = {
    enable = true;
    datasets = { };
  };

  # Syncoid for replication (optional, for backing up to remote ZFS)
  # services.syncoid = {
  #   enable = true;
  #   commands = {};
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
