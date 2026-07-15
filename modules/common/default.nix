{ config, pkgs, ... }:
{
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
    ./nix.nix
    ./users.nix
    ./network
    ./zfs
    ./zsh
  ];
}
