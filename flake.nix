{
  description = "Hlamnix (a.k.a. Hlamlab 3.0)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Disko is required for nix-anywhere to partition the disk automatically
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # disko-zfs for declarative ZFS dataset management
    disko-zfs = {
      url = "github:numtide/disko-zfs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };

    # sops-nix for secrets management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, disko-zfs, sops-nix, ... }@inputs: {
    nixosConfigurations = {

      # 1. The Simulation (Proxmox VM)
      playground = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          disko-zfs.nixosModules.default
          sops-nix.nixosModules.sops

          ./hosts/playground/configuration.nix
        ];
      };
    };
  };
}
