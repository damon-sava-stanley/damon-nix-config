# deeley NixOS configuration

Minimal NixOS 26.05 configuration for the `deeley` host and `damon` user.

The system uses:

- niri on Wayland
- greetd with tuigreet
- Home Manager
- Fish
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
nix fmt $(git ls-files '*.nix')
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

## Sleep and power

Automatic sleep is based on keyboard/mouse inactivity in the graphical session,
not lid position. Closing the lid does not lock, blank, or suspend on either
power source, so external-monitor use with the lid closed is uninterrupted.

Idle locks after five minutes and blanks displays after ten minutes. On AC the
machine stays awake: zettel, its tunnel, and associated services remain available.
On battery, 30 minutes idle triggers suspend, followed by hibernate five minutes
later. Unplugging after the 30-minute idle threshold starts battery sleep within
about two seconds; activity cancels the pending idle sleep.
Manual `systemctl suspend`, `hibernate`, and `suspend-then-hibernate` still work;
no services execute during actual suspend or hibernation.

Implementation: `modules/nixos/power-policy.nix`, `scripts/power-policy.py`, and
the swayidle configuration in `home/damon/default.nix`. All logind lid actions
are ignored. The user `power-policy-idle.service` is armed by swayidle and
cancelled on activity; there is no system lid watcher. Automatic idle sleep
requires the graphical session and swayidle to be running. Closing the lid is
not a security action: explicitly lock before putting the laptop away, and
manually sleep it before placing it in a bag.

After deployment, verify closed-lid external-monitor work remains uninterrupted
on both power sources, and test idle lock/blank and battery suspend/hibernate.
Hibernate/resume and display recovery need real-hardware testing. Inspect
`journalctl --user -u power-policy-idle` and
`journalctl -u systemd-suspend-then-hibernate` for issues.

## Cloudscape wallpaper

A slowly drifting Solarized cloud shader replaces the static Nix wallpaper.
`cloudscape.service` manages one low-resolution renderer per enabled monitor;
the existing theme watcher blends its palette when Darkman changes mode.
Renderers stop while swaylock is running or their displays are powered off,
and restart on wake. Output changes are reconciled automatically.

See [`home/damon/cloudscape/README.md`](home/damon/cloudscape/README.md) for
architecture, controls, validation, and current lifecycle limitations.

## Manual screensaver

`Super+Shift+T` launches Flying Toasters fullscreen on one display; press
`Escape` to dismiss it. It never starts automatically, and repeated shortcut
presses do not open extra copies. You can also run `niri-flying-toasters`.

While the animation is running, SDL inhibits niri's idle detection, suppressing
swayidle's automatic lock, display-off, and suspend timers. Closing it (including
a crash) releases inhibition automatically and normal idle timing resumes.
Dismiss it rather than just switching workspaces: inhibition can remain active
while it is hidden. swayidle itself stays running, so explicit locking and
locking before sleep still work.
This is decoration, not a lock screen: use `Super+Shift+S` when security matters.

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
