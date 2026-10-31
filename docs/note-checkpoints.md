# Note checkpoint service

Managed by `home/damon/note-checkpoint.nix`; implementation is
`home/damon/bin/note-checkpoint.py`. Host config declares `users.users.damon.linger = true`.

The user service commits text-note changes and pushes to the private
`damon-sava-stanley/remote-zettel-notes` repository every two minutes. Notes remain
in `~/Dropbox/000_zettelkasten`; metadata, lock and status remain in
`~/.local/state/zettel-checkpoint`. No metadata is stored in Dropbox. Existing user
SSH authentication is used, with noninteractive authentication and connection timeout.
Python, Git and OpenSSH are explicit Nix runtime dependencies.

Only nonhidden Markdown/BibTeX, `references/sources.json` and root `.gitignore`
are selected. PDFs, HTML and other attachments are excluded. No automatic pull,
restore, force push or live-note mutation. Push failures preserve local commits;
unchanged invocations retry pushes. This is periodic recovery, not atomic snapshots
or application pre-write gating. Same-user processes can alter history; GitHub is
private plaintext storage, not end-to-end encrypted backup.

## Status and manual use

```sh
systemctl --user start zettel-checkpoint.service
systemctl --user list-timers zettel-checkpoint.timer
journalctl --user -u zettel-checkpoint.service -n 20
python3 -m json.tool ~/.local/state/zettel-checkpoint/status.json
```

## Migration performed 2026-10-31

Built only the Home Manager-generated checkpoint units and their executable, and
replaced the two manual live units with symlinks to those outputs. The persistent
GC root is `~/.local/state/zettel-checkpoint/nix-units`; retain it until a full
Home Manager generation owns the units. Previous manual unit files are retained in
`~/.local/state/zettel-checkpoint/pre-nix-units-*`. The old script under
`~/.local/lib/zettel-checkpoint/` is no longer used.

No full NixOS or Home Manager activation was performed: unrelated pending host
changes were deliberately not deployed. On the next reviewed system activation,
Home Manager will replace these two transitional unit symlinks (`force = true` is
scoped to these exact paths). It will then own the service and timer normally.
The Git history, credentials and remote are unchanged. A real checkpoint/push
succeeded using the Nix-built executable after handoff.

The canonical implementation now lives in this configuration repository, not the
older source copies in Remote Zettel. Edit/build here for subsequent changes.

## Verification

```sh
nix build .#checks.x86_64-linux.note-checkpoint
```

The check asserts the evaluated paths, remote, schedule, private umask and lingering;
it runs offline tests for history, deletion, no-op commits, failed push/retry,
attachment/hidden-file exclusion and literal wildcard filenames. No real notes or
network are used by the check. Use `path:$PWD#checks.x86_64-linux.note-checkpoint`
while new files are untracked, or add the intended files before normal flake builds.

Recover into a separate private clone and inspect before copying any files back.
Never reset the live Dropbox directory automatically.
