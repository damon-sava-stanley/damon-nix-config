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
`Super+Shift+S` to lock the session.

## Dictation

Right Alt is a system-wide hold-to-dictate key. Hold it while speaking and
`dictate` locally streams speech through Whisper, then types each completed
chunk into the focused Wayland input. Release Right Alt to stop listening. The
first chunk normally takes about 2.5–3 seconds, so keep holding until text
starts to appear for short utterances.

The integration is local-only and uses PipeWire, a Vulkan-enabled
`whisper-stream`, the multilingual large-v3-turbo Q5 model, and `wtype`. Right
Alt is consumed by keyd on every keyboard and is no longer available as a
regular AltGr key.

After first enabling the configuration, reboot (or fully log out and back in)
so the new `keyd` group membership applies. Useful diagnostics are:

```console
dictate-control status
dictate --list-devices
systemctl --user status dictate-key-listener.service
journalctl --user -u dictate-key-listener.service
tail -f "$XDG_RUNTIME_DIR/dictate/dictate.log"
```

`dictate-control stop` is a manual safety stop. Microphone selection defaults
to dictate's USB/Bluetooth/digital/analog priority; use `dictate
--list-devices` to see what it detects if the wrong source is chosen.

## Install from an existing NixOS system

From the repository checkout, copy the configuration into `/etc/nixos`, replace
the placeholder with the machine's generated hardware configuration, verify
that it builds, and activate it:

```console
./install.sh
```
