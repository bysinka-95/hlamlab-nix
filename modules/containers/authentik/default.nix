{ ... }:
{
  imports = [
    ./container.nix
    ./traefik.nix
  ];

  # DNS entry for internal container-to-container communication (if needed)
  # and to prevent 404s in Traefik (though Traefik uses its own routers)
  networking.hosts."10.0.0.5" = [ "auth" "authentik" ];
}
