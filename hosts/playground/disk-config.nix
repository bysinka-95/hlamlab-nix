# ZFS-based disk configuration with declarative dataset management
#
# This configuration is the SINGLE SOURCE OF TRUTH for all ZFS datasets.
# disko-zfs automatically detects and manages datasets declared here.
#
# During initial installation (nixos-anywhere):
# - Creates base ZFS structure (pool, root datasets)
# - Creates initial service datasets (opencloud, immich)
#
# After installation (nixos-rebuild switch):
# - disko-zfs automatically detects changes to this file
# - Creates new datasets, updates properties, applies quotas
# - No manual 'zfs create' commands needed!
#
# To add a new service:
# 1. Add dataset declaration to this file (see template at bottom)
# 2. Run: nixos-rebuild switch
# 3. Dataset is automatically created with all properties
#
# To update properties (quota, compression, etc.):
# 1. Edit values in this file
# 2. Run: nixos-rebuild switch
# 3. Properties automatically updated
#
# This provides:
# - Single source of truth for all datasets (installation + runtime)
# - Declarative dataset management via nixos-rebuild
# - Automatic property updates
# - Infrastructure-as-code

{ ... }:
{
  disko.zfs.enable = true;
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        device = "/dev/sda"; # The hard drive
        content = {
          type = "gpt";
          partitions = {
            # BIOS Boot partition (Required for GRUB in BIOS mode)
            boot = {
              size = "1M";
              type = "EF02"; # for grub MBR
            };
            # EFI System Partition
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            # ZFS partition (rest of disk)
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "tank";
              };
            };
          };
        };
      };
    };

    # ZFS pool configuration
    zpool = {
      tank = {
        type = "zpool";
        # Root filesystem options
        rootFsOptions = {
          compression = "lz4"; # Fast compression
          acltype = "posixacl"; # POSIX ACLs
          xattr = "sa"; # Extended attributes
          atime = "off"; # Don't update access time (performance)
          "com.sun:auto-snapshot" = "false";
        };

        # ZFS datasets
        datasets = {
          # Root filesystem
          root = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "/";
          };

          # Nix store (no snapshots needed)
          nix = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options = {
              mountpoint = "/nix";
              atime = "off";
              "com.sun:auto-snapshot" = "false";
            };
          };

          # Home directories
          home = {
            type = "zfs_fs";
            mountpoint = "/home";
            options.mountpoint = "/home";
          };

          # Container services (parent dataset)
          "services" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/services";
            options.mountpoint = "/var/lib/services";
          };

          # Service datasets (managed by disko-zfs)
          # disko-zfs automatically applies changes when you rebuild
          "services/opencloud" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/var/lib/services/opencloud";
              quota = "50G";
              reservation = "10G";
              compression = "lz4";
              atime = "off";
              "com.sun:auto-snapshot" = "true";
            };
          };

          "services/immich" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/var/lib/services/immich";
              quota = "300G";
              reservation = "10G";
              compression = "lz4";
              atime = "off";
              "com.sun:auto-snapshot" = "true";
            };
          };

          "services/collabora" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/var/lib/services/collabora";
              quota = "20G";
              reservation = "5G";
              compression = "lz4";
              atime = "off";
              "com.sun:auto-snapshot" = "true";
            };
          };

          # Snapshots storage
          "backups" = {
            type = "zfs_fs";
            mountpoint = "/var/backups";
            options = {
              mountpoint = "/var/backups";
              compression = "gzip"; # High compression for backups
              "com.sun:auto-snapshot" = "false";
            };
          };

          # Template for adding new services:
          # "services/myservice" = {
          #   type = "zfs_fs";
          #   options = {
          #     mountpoint = "/var/lib/services/myservice";
          #     quota = "100G";           # Disk space limit
          #     reservation = "20G";      # Guaranteed space
          #     compression = "lz4";      # Enable compression
          #     atime = "off";            # Performance
          #     "com.sun:auto-snapshot" = "true";  # Enable snapshots
          #   };
          # };
        };
      };
    };
  };
}

