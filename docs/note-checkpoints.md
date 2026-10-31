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

Initially switched only isolated Nix-built units, then the operator activated the
host configuration. Verified the live units now link through the active Home Manager
files generation. Removed `~/.local/state/zettel-checkpoint/nix-units` and the unused
manual script under `~/.local/lib/zettel-checkpoint/`. Prior manual unit copies remain
in `~/.local/state/zettel-checkpoint/pre-nix-units-*` for reference. Git history,
credentials and remote were preserved; the periodic timer remains enabled.

The canonical implementation now lives in this configuration repository, not the
older source copies in Remote Zettel. Edit/build here for subsequent changes.

## Application bridge (deployed and live-smoked)

`modules/note-checkpoint-bridge.nix` defines a system service running as `damon`,
with a private runtime socket `/run/zettel-checkpoint/control.sock`. It authenticates
Linux peer UID `remote-zettel` and accepts only `{"version":1,"op":"checkpoint"}`
followed by a newline. It invokes fixed local-only argv; the request cannot specify
paths, commands, remotes or environment. Response binds the fixed root and commit.

The sandbox mounts notes read-only and backup state read-write, hides the rest of
home including SSH credentials, and has no network. The existing user timer retains
push responsibility. Both paths serialize on the same existing filesystem lock.
Requests have byte/time limits; subprocess timeout kills its process group. All
returned failures are generic. Same-owner processes remain outside this boundary.

Deeley now pins checkpoint-capable Remote Zettel revision
`56e33577549b7039fd88b4b4782fffe2db0cd81d` and configures:

```nix
services.zettel-checkpoint-bridge.enable = true;
services.remote-zettel.noteCheckpointSocket = "/run/zettel-checkpoint/control.sock";
```

These switches are active on Deeley. Disposable-note chat creation/edit, recovery,
stopped-bridge write denial, restart/retry and cleanup passed; see
[the deployment record](deployments/note-checkpoint-gates.md). Run the existing user checkpoint first:
the bridge requires the note and backup-state directories to already exist. The
application's expected root is the host dataRoot, not its private service alias.
Background/manual writes are unchanged; only interactive create/edit tools are gated.
There is no backup-health UI or whole-prompt cancellation lifecycle yet. See Remote
Zettel's `docs/note-checkpoints.md` and ADR 010 for the full contract and limitations.

## Verification

```sh
nix build .#checks.x86_64-linux.note-checkpoint \
  .#checks.x86_64-linux.note-checkpoint-bridge \
  .#checks.x86_64-linux.note-checkpoint-bridge-vm
```

The check asserts the evaluated paths, remote, schedule, private umask and lingering;
it runs offline tests for history, deletion, no-op commits, failed push/retry,
attachment/hidden-file exclusion and literal wildcard filenames. No real notes or
network are used by the check. Use `path:$PWD#checks.x86_64-linux.note-checkpoint`
while new files are untracked, or add the intended files before normal flake builds.

Recover into a separate private clone and inspect before copying any files back.
Never reset the live Dropbox directory automatically.
