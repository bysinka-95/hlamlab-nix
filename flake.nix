{
  description = "Hlamnix (a.k.a. Hlamlab 3.0)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    # deploy-rs drives remote deploys with magic rollback (see README § Deploy).
    # `follows` collapses the second nixpkgs out of the lock — deploy-rs pins one
    # from 2025-03-26, and a stale pin is what broke deploys in the first place.
    # Safe to follow only because the deployPkgs overlay below means deploy-rs'
    # own Rust is never compiled here; the binary comes prebuilt from nixpkgs.
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

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

  outputs = inputs@{ self, flake-parts, deploy-rs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import inputs.nixpkgs { inherit system; };

      # deploy-rs' *lib* (the activation wrapper baked into every deployed
      # generation) paired with nixpkgs' prebuilt *binary*.
      #
      # Building deploy-rs from its own flake drags in the nixpkgs it pins —
      # 2025-03-26 as of this writing — whose `fetchCrate` still downloads from
      # `crates.io/api/v1/crates/<name>/<version>/download`. crates.io answers 403
      # there now; current nixpkgs fetches `static.crates.io` instead. So the pin
      # meant to stop a `nix flake update` breaking the deploy tool broke it by
      # going stale, and deploys died compiling cbitset 0.2.0 on the target.
      #
      # nixpkgs ships deploy-rs prebuilt in cache.nixos.org, so this fixes the
      # fetch and means no Rust is ever compiled on the host. Idiom is from
      # deploy-rs' own README.
      deployPkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          deploy-rs.overlays.default
          (final: prev: { deploy-rs = { inherit (pkgs) deploy-rs; lib = prev.deploy-rs.lib; }; })
        ];
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
    systems = [ system ];

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
            deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.playground;
        };
      };

      # deploy-rs' own validation of the `deploy` attribute above, wired into
      # `nix flake check` — which deploy-rs runs itself before every deploy.
      # x86_64-linux only: both checks embed `profiles.*.path`, so they depend on
      # the target's system closure and cannot be realised on different architectures.
      # There nix skips them ("omitted these incompatible systems:
      # x86_64-linux"); they fire from CI or any Linux builder.
      checks.${system} = deployPkgs.deploy-rs.lib.deployChecks self.deploy;
    };
  };
}
