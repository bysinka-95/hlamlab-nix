# Collabora Service Module
#
# This module provides a complete Collabora Online deployment including:
# - NixOS container with Collabora service
# - Traefik reverse proxy configuration
# - DNS entry in /etc/hosts for internal resolution
# - External storage bind mount for state persistence

{ ... }:
{
  imports = [
    ./container.nix
    ./traefik.nix
    ./host.nix
  ];
}

