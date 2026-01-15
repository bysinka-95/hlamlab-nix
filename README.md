# Hlamlab NixOS homelab

Flake-based NixOS configuration for the homelab. `playground` is the current Proxmox VM target used to iterate toward
the eventual host migration.

## Repo layout

- `flake.nix`: Inputs (nixpkgs, disko, home-manager) and `nixosConfigurations` outputs.
- `modules/common/`: Shared defaults (nix settings, allowUnfree, SSH policy, base packages).
- `hosts/playground/`
    - `configuration.nix`: System config (boot, networking, SSH, root keys, base packages, home-manager for root).
    - `disk-config.nix`: Disko layout for `/dev/sda` (GPT + ESP + ext4 root).
    - `hardware-configuration.nix`: Generated hardware profile; replace/regenerate per machine.

## Prerequisites

- Nix with flakes enabled on the build machine.
- SSH reachability to the target (root or nixos user) and your SSH public key present on the target.
- For fresh installs: access to the target disk (`/dev/sda` assumed) and ability to reboot.
- Tools (install via Nix if needed):
    - `nixos-anywhere` for remote installs.
    - `nixos-rebuild` via `nix run nixpkgs#nixos-rebuild` for deploys.
- Default admin user: `hlamnix` (wheel/networkmanager). Set its hashed password in `hosts/playground/configuration.nix`
  by replacing `<replace-with-mkpasswd-sha512>` with the output of `mkpasswd -m sha-512`.

## Bootstrap a fresh host (example: playground VM)

1. (Optional) Update the disk layout in `hosts/playground/disk-config.nix` to match the target device.
2. Set the `hlamnix` password hash in `hosts/playground/configuration.nix`:
   ```sh
   mkpasswd -m sha-512
   ```
   Paste the result into `hashedPassword` for `hlamnix`.
3. Install remotely with nixos-anywhere (runs disko + config):
   ```sh
   nix run github:nix-community/nixos-anywhere -- \
     --flake '.#playground' \
     --generate-hardware-config nixos-generate-config ./hosts/playground/hardware-configuration.nix \
     --target-host nixos@<playground-ip>
   ```
    - Replace `<playground-ip>` with the VM IP.
    - After install, the host will reboot into the flake-defined system.

## Rebuild / deploy changes

Run from the repo root after editing configs (ensure `hlamnix` hashed password is set in the config):

```sh
nix run nixpkgs#nixos-rebuild -- switch \
  --flake .#playground \
  --target-host hlamnix@<playground-ip> \
  --build-host hlamnix@<playground-ip> \
  --use-remote-sudo \
  --ask-sudo-password
```

- To build locally and push the closure: replace `--build-host hlamnix@<playground-ip>` with `--build-host localhost`.
- Add `--fast` for a quicker dry-run.

## Add a new host

1. Copy `hosts/playground` to `hosts/<new-host>` and adjust:
    - Hostname and networking in `configuration.nix`.
    - Disk device/partitions in `disk-config.nix`.
    - Generate a new `hardware-configuration.nix` on the target (`nixos-generate-config`).
2. Add the host to `flake.nix` under `nixosConfigurations` with the correct `system`.
3. Install with nixos-anywhere (or manual ISO) and rebuild via `nixos-rebuild` using `.#<new-host>`.

## Disk layout (disko)

- Current layout: GPT on `/dev/sda`, 1M BIOS boot (EF02), 512M ESP at `/boot` (vfat), remaining ext4 root at `/`.
- To change disks or sizes, edit `hosts/<host>/disk-config.nix`; nixos-anywhere will partition/format accordingly.

## SSH keys and access

- Root SSH login is disabled; SSH as `hlamnix` (password auth enabled) or add your key to its `authorizedKeys` (shared
  with root in the config).
- Root SSH keys live in `hosts/<host>/configuration.nix` under `users.users.root.openssh.authorizedKeys.keys` and are
  reused for `hlamnix`.

## Updating inputs

- Update flakes (nixpkgs, home-manager, disko):
  ```sh
  nix flake update
  ```
- Review `flake.lock` changes and rebuild the target to apply.

## Troubleshooting / validation

- Check SSH: `ssh root@<playground-ip> hostname`.
- Validate flake: `nix flake check` (add tests as they are added).
- Inspect logs on host: `journalctl -u nixos-rebuild -u sshd` or `journalctl -b`.
- If hardware changes, regenerate `hardware-configuration.nix` on the host and copy it back.

## Notes for future hardening

- Root SSH login is already disabled; consider moving to key-only access for `hlamnix` once the password is confirmed
  working.
- Consider secrets management (e.g., sops-nix + age) instead of embedding keys.
- Add automated checks (CI) to run `nix flake check` on changes.
