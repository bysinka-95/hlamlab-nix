{ config, ... }:
{
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # Optimise the store automatically on every build/fetch
      auto-optimise-store = true;
      # deploy-rs (and `nixos-rebuild --build-host`) connect as a wheel user and
      # pass client-side settings such as `store`. Without this the daemon logs
      # "ignoring the client-specified setting 'store', because it is a restricted
      # setting and you are not a trusted user" on every deploy. @wheel already has
      # NOPASSWD sudo, so this grants nothing it did not already have.
      trusted-users = [ "root" "@wheel" ];

      # Safety net: start freeing space mid-build once free space drops below
      # min-free, and stop once max-free is available. Only collects unreachable
      # store paths — never touches generations.
      min-free = 1024 * 1024 * 1024; # 1 GiB
      max-free = 5 * 1024 * 1024 * 1024; # 5 GiB
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
  };

  # Automatic System Upgrades
  system.autoUpgrade = {
    enable = true;
    dates = "04:00";
    # Dynamically targets the configuration for the current host
    flake = "github:bysinka-95/hlamlab-nix#${config.networking.hostName}";
    # Do NOT reboot automatically if a new kernel/initrd is built
    # This option is lacking deploy-rs' magic-rollback.
    allowReboot = false;
  };
}
