{ modulesPath, ... }:

{
  imports = [
    ../../modules/secrets
    ../../modules/common
    ./disk-config.nix
    ./hardware-configuration.nix
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Bootloader
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Networking
  networking = {
    hostName = "playground";
    networkmanager.enable = true;
  };

  # User Configuration
  users.users.hlamnix = {
    isNormalUser = true;
    description = "Hlamnix admin user";
    extraGroups = [ "wheel" "networkmanager" ];
    hashedPassword = "$6$jpPlddmu.tNy0i5N$fk1GPeQs.MknesNIEj0KmnsW9/9lKdg/XOk10B3WZpwAITfFr.3Km0/D3E5smjslj/RORzdkd7hODZKj37A8J."; # Set with mkpasswd -m sha-512
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH5cl6RrQsY3tQ0GY8XmN7dWC0SSifxwbMuBl7T/yufW hoholms@hoholmsmac.local"
    ];
  };

  # Home Manager Setup
  home-manager.users.root = { pkgs, ... }: {
    home.stateVersion = "26.05";
    programs.zsh.enable = true;
  };

  system.stateVersion = "26.05";
}
