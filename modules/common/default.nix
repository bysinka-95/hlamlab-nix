{ pkgs, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    vim
    nano
    git
    curl
    bat
    eza
    fastfetch
    zsh-history-substring-search
  ];

  imports = [
    ./settings.nix
    ./users.nix
    ./network
    ./zfs
    ./zsh
  ];
}
