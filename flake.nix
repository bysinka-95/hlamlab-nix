{
  description = "Hlamnix (a.k.a. Hlamlab 3.0)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    # deploy-rs drives remote deploys with magic rollback (see README § Deploy).
    # Deliberately NOT `follows`-ing nixpkgs: deploy-rs pins the nixpkgs it is tested
    # against, and its activation wrapper is baked into every deployed generation.
    # Pointing it at nixos-unstable would rebuild the Rust crate against whatever
    # toolchain unstable ships that week — a deploy tool is the last thing that
    # should break on a `nix flake update`.
    deploy-rs.url = "github:serokell/deploy-rs";

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

  outputs = inputs@{ self, flake-parts, deploy-rs, ... }: flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ "x86_64-linux" ];

    flake = {
      nixosConfigurations = {
        # 1. The Simulation (Proxmox VM)
        playground = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            inputs.disko.nixosModules.disko
            inputs.disko-zfs.nixosModules.default
            inputs.sops-nix.nixosModules.sops

            ./hosts/playground/configuration.nix
          ];
        };
      };

      # Deploy targets. Settings cascade: deploy < node < profile, so anything set
      # here is the default for every future host.
      deploy = {
        # SSH in as the admin user; activate the profile as root (via sudo — the
        # NOPASSWD wheel rule in hosts/playground/configuration.nix is what makes
        # this non-interactive).
        sshUser = "hlamnix";
        user = "root";

        # Build on the target. The workstation might bedifferent architecture (i.e. aarch64-darwin)
        # and cannot build x86_64-linux; this also keeps the closure off the LAN.
        remoteBuild = true;

        # Roll back if activation fails outright...
        autoRollback = true;
        # ...and if the host stops answering SSH after activation (bad firewall,
        # broken sshd, dead NIC). Requires the confirmation round-trip below.
        magicRollback = true;

        # A switch here restarts ~10 nspawn containers; the 240s default is tight.
        activationTimeout = 600;
        # The confirmation SSH lands while those containers are still coming up.
        confirmTimeout = 120;

        nodes.playground = {
          hostname = "playground.local";
          profiles.system.path =
            deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.playground;
        };
      };

      # deploy-rs' own validation of the `deploy` attribute above, wired into
      # `nix flake check` — which deploy-rs runs itself before every deploy.
      # x86_64-linux only: both checks embed `profiles.*.path`, so they depend on
      # the target's system closure and cannot be realised on different architectures.
      # There nix skips them ("omitted these incompatible systems:
      # x86_64-linux"); they fire from CI or any Linux builder.
      checks.x86_64-linux = deploy-rs.lib.x86_64-linux.deployChecks self.deploy;
    };
  };
}
