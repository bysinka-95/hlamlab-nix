{ ... }:
{
  imports = [
    ./container.nix
    ./traefik.nix
  ];

  networking.hosts."10.0.0.5" = [ "kanidm" ];
}
