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
    };

    # Periodic store optimisation (finding and hard-linking duplicate files)
    optimise = {
      automatic = true;
      dates = [ "weekly" ];
    };
  };

  # Automatic System Upgrades — DISABLED.
  #
  # This pulls the *pushed* repo, which is not what deploy-rs put on the host. The
  # committed hosts/playground/configuration.nix still carries placeholder values
  # (domain = "yourdomain.com", hostId = "1a23bc45"); the real ones live only in the
  # working tree. A nightly unattended switch would therefore activate a generation
  # with the wrong `networking.hostId`, and the next boot would fail to
  # `zpool import tank` on a root-on-ZFS host.
  #
  # Before re-enabling: push a commit that actually reproduces the running host, and
  # accept that deploys of unpushed local changes then survive only until 04:00.
  # It also has no equivalent of deploy-rs' magic rollback, so a bad pushed commit
  # activates unattended with nothing to catch it.
  system.autoUpgrade = {
    enable = false;
    dates = "04:00";
    # Dynamically targets the configuration for the current host
    flake = "github:bysinka-95/hlamlab-nix#${config.networking.hostName}";
    # Do NOT reboot automatically if a new kernel/initrd is built
    allowReboot = false;
  };
}
