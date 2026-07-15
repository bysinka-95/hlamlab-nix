{ lib, ... }:
{
  # NAT so containers can reach the outside world
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-+" ];
    externalInterface = lib.mkDefault "ens18"; # adjust if your host NIC differs
  };

  # Import service modules (each directory contains container + traefik + DNS + host integration)
  imports = [
    ./frame.nix
    ./opencloud.nix
    ./immich.nix
    ./collabora.nix
    ./authelia.nix
    ./lldap.nix
    ./vaultwarden.nix
    ./searx.nix
  ];
}
