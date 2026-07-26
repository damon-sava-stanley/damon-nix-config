# deeley NixOS configuration

Minimal NixOS 26.05 configuration for the `deeley` host and `damon` user.

The system uses:

- niri on Wayland
- greetd with tuigreet
- Home Manager
- Neovim
- Brave
- Ghostty
- fuzzel

## Before installing

The checked-in `hosts/deeley/hardware-configuration.nix` is intentionally a
placeholder. From the NixOS installer, after mounting the target filesystems
under `/mnt`, generate the machine-specific configuration:

```console
sudo nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix hosts/deeley/hardware-configuration.nix
```

Review the generated filesystems, swap devices, and initrd modules before
installing. GPU-specific settings can be added later.

## Validate

Create and commit the lock file on a machine with Nix:

```console
nix flake lock
nix fmt
nix flake check
```

To build just this host:

```console
sudo nixos-rebuild build --flake .#deeley
```

## Install

From the repository on the NixOS installer:

```console
sudo nixos-install --flake .#deeley
sudo nixos-enter --root /mnt -c 'passwd damon'
```

The second command sets the initial login password without storing it in Git or
the world-readable Nix store.

After installation, use:

```console
sudo nixos-rebuild switch --flake .#deeley
```

The first graphical login appears through tuigreet. In niri, use
`Super+Return` for Ghostty, `Super+D` for fuzzel, `Super+B` for Brave, and
`Super+Shift+L` to lock the session.
