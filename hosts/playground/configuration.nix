{ modulesPath, ... }:

{
  imports = [
    ../../modules/secrets
    ../../modules/common
    ../../modules/containers
    ./disk-config.nix
    ./hardware-configuration.nix
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # Environment Settings
  hlamlab.settings = {
    domain = "yourdomain.com";
    tunnelId = "00000000-0000-0000-0000-000000000000f";
    hostId = "1a23bc45";
  };

  # Observability: inject node_exporter + persistent journald into every
  # container so Prometheus can scrape and the host Alloy captures all logs.
  hlamlab.observability.enable = true;

  # Container Services Enablement
  hlamlab.services = {
    authelia.enable = true;
    collabora.enable = true;
    grafana.enable = true;
    immich.enable = true;
    lldap.enable = true;
    loki.enable = true;
    opencloud.enable = true;
    prometheus.enable = true;
    searx.enable = true;
    vaultwarden.enable = true;
    blocky.enable = true;
    gotify.enable = true;
    gatus.enable = true;
  };

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

  # deploy-rs SSHes in as `hlamnix` and activates as root, non-interactively.
  # Swap this for `interactiveSudo = true` on the node in flake.nix if you would
  # rather type the password on every deploy.
  #
  # Use the module's own option rather than a hand-written `extraRules` entry: an
  # extra rule is appended *after* the module's order-600 wheel rule, and sudoers is
  # last-match-wins, so it silently drops the `SETENV` tag and breaks `sudo -E`.
  security.sudo.wheelNeedsPassword = false;

  time.timeZone = "Europe/Chisinau";

  # nixpkgs recently added `systemd-machined.socket` to the upstream unit set. On a
  # host running nspawn containers, the containers D-Bus-activate
  # systemd-machined.service before switch-to-configuration gets round to starting
  # the socket, which then dies with:
  #   systemd-machined.socket: Socket service systemd-machined.service already active, refusing.
  # That failed unit makes the whole switch exit non-zero — and deploy-rs rolls back.
  # The socket only exposes machined's optional Varlink API; the service itself is
  # D-Bus activated, so machinectl / nixos-container / journalctl -M keep working.
  # Suppress (drop from /etc), do NOT mask: masking a *running* machined makes
  # systemd ignore its watchdog pings and SIGABRT it three minutes later.
  systemd.suppressedSystemUnits = [ "systemd-machined.socket" ];

  system.stateVersion = "26.05";
}
