{
  # This configures /dev/sda with a standard GPT partition table.
  # It works for both BIOS (Legacy) and UEFI booting.
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
            # EFI System Partition (ESP)
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            # Root Partition (The rest of the disk)
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
