# Immich Service Module
#
# This module provides a complete Immich deployment including:
# - NixOS container with Immich, PostgreSQL, Redis, and ML services
# - Traefik reverse proxy configuration (router, middleware, service)
# - DNS entry in /etc/hosts for internal resolution
# - External storage bind mount for media persistence
#
# Structure:
#   container.nix - Container definition with external storage
#   traefik.nix   - Traefik routing configuration
#
# Storage: /var/lib/services/immich on host → mounted in container as /var/lib/immich
# This ensures photos/videos survive container recreation
#
# Usage: Import this directory from modules/containers/default.nix

{ ... }:
{
  imports = [
    ./container.nix
    ./traefik.nix
  ];

  # DNS entry: Allows Traefik to reach "http://immich" instead of "10.0.0.3"
  networking.hosts."10.0.0.3" = [ "immich" ];
}

