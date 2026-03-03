{ pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [ nano git curl ];

  imports = [
    ./users.nix
    ./network
    ./zfs
  ];
}
