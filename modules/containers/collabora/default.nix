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
  ];

  # DNS entry: Allows Traefik to reach "http://collabora" instead of "10.0.0.4"
  networking.hosts."10.0.0.4" = [ "collabora" ];
}

