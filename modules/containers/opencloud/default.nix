# OpenCloud Service Module
#
# This module provides a complete OpenCloud deployment including:
# - NixOS container with OpenCloud service
# - Traefik reverse proxy configuration (router, middleware, service)
# - DNS entry in /etc/hosts for internal resolution
# - External storage bind mount for state persistence
#
# Structure:
#   container.nix - Container definition with external storage
#   traefik.nix   - Traefik routing configuration
#
# Storage: /var/lib/services/opencloud on host → mounted in container as /var/lib/opencloud
# This ensures state and user data survive container recreation
#
# Usage: Import this directory from modules/containers/default.nix

{ ... }:
{
  imports = [
    ./container.nix
    ./traefik.nix
    ./host.nix
  ];
}

