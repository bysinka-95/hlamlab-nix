{
  description = "Hlamnix (a.k.a. Hlamlab 3.0)";

  inputs = {
      nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

      # Disko is required for nix-anywhere to partition the disk automatically
      disko.url = "github:nix-community/disko";
      disko.inputs.nixpkgs.follows = "nixpkgs";

      # Home Manager
      home-manager.url = "github:nix-community/home-manager";
      home-manager.inputs.nixpkgs.follows = "nixpkgs";
    };

    outputs = { self, nixpkgs, disko, home-manager, ... }: {
      nixosConfigurations = {

        # 1. The Simulation (Proxmox VM)
        playground = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            home-manager.nixosModules.home-manager

            ./hosts/playground/configuration.nix
          ];
        };
      };
    };
}
