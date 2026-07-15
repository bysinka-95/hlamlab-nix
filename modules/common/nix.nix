{ config, ... }:
{
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # Optimise the store automatically on every build/fetch
      auto-optimise-store = true;
    };

    # Automatic Garbage Collection to keep disk usage under control
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };

    # Periodic store optimisation (finding and hard-linking duplicate files)
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };

    # Safety net: trigger GC automatically when free space drops below 1GB
    extraOptions = ''
      min-free = ${toString (1024 * 1024 * 1024)}
      max-free = ${toString (5 * 1024 * 1024 * 1024)}
    '';
  };

  # Automatic System Upgrades
  system.autoUpgrade = {
    enable = true;
    dates = "04:00";
    # Dynamically targets the configuration for the current host
    flake = "github:bysinka-95/hlamlab-nix#${config.networking.hostName}";
    # Reboot automatically if a new kernel/initrd is built
    allowReboot = true;
  };
}
