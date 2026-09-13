{ ... }:
{
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      # Hard-link duplicate files as they land in the store. This is the
      # continuous form of `nix-store --optimise`, so no periodic optimise job.
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
  };

  # No system.autoUpgrade: deploys go through deploy-rs, which has magic rollback
  # and carries the working tree rather than the last pushed commit.
}
