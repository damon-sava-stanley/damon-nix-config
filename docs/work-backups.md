# Maintained Work backups

Status: **implemented and offline/VM-tested; not activated or live-smoked.** The
separate one-time pilot backups remain valid and are not replaced or deleted.

## Policy

`services.remote-zettel-work-backup.enable` installs a root system service and
03:00 **local-time** timer, with one-minute accuracy, no random delay, and no missed
run catch-up. Inactive services or busy Work stores cause a skip, not cancellation.
There is no automatic retention/deletion, network upload code, publisher, or model
request. Monitor local disk and Dropbox quota; these archives include retained code.

The service first checks idleness without disruption. It then stops only the web
service to prevent new queueing and rechecks coordinator, host admission and both
executor stores. An admission race restarts web and skips; it never stops an active
host/executor to force a backup. Once drained, all four services are stopped for
capture. Do not edit task Markdown externally during a manual capture; no writer
on another Dropbox device can be locked by this service. GNU tar reports changing
files as a failure, but this is not a distributed-document snapshot protocol.

Capture is uncompressed and limited to 120 seconds; services resume before gzip,
verification and replication. The timeout kills the capture process group before
restarting services. Service-control calls have their own 180-second limits; the
120-second limit is not an absolute guarantee on total downtime during failures.
A root-private recovery record is durable before every stop. Python cleanup and
systemd `ExecStopPost` restart only services recorded by this invocation. SIGKILL
is VM-tested; a machine power loss is not an online recovery operation. Inspect
service health and the recovery record after an unclean boot. Manual maintenance
must not concurrently stop/start the same units during a backup.

## Contents and paths

Local bundles live under `/var/backups/remote-zettel-work`, root-owned mode 0700.
The bundle includes:

- Task documents at `/home/damon/Dropbox/agent-workspace`.
- Coordinator Work SQLite, host admission ledger/journals, executor stores/output
  and retained checkouts, trusted offline source, and executor scratch documents.
- ACLs, extended attributes and numeric ownership inside `work.tar.gz`.
- A nonsecret configuration/generation/unit-property record, verification summary,
  and checksums. Unit environment/credential contents are not dumped.

**`credentials.sqlite*` is excluded**, including WAL/SHM and credential ownership
DBs; the private host socket is excluded. Operational ownership DBs are retained,
but no lock is treated as authority to resume a model run. GNU tar never follows
repository/operation symlinks. Verification rejects traversal and credential names,
checks required databases, and copies only known operational SQLite payloads into
private temporary files for integrity checks. Archive links are never extracted
or followed. Arbitrary SQLite files inside repositories are not opened by verification.

Completed uniquely named local bundles are checksummed and fsynced before
publication. Failed `.pending-*` captures remain for private operator inspection;
no previous snapshot is overwritten. A replication failure can leave a valid local
snapshot but no Dropbox copy; status reports failure and retains the previous
`lastCompleted` value. There is currently no automatic retry of that exact bundle;
a later invocation creates a new snapshot.

Dropbox destination: `~/Dropbox/Backups/remote-zettel-work`, owner `damon`, mode 0700.
Prepare it **as the owner before activation**, without symlinks or sharing it with
agent services. The module deliberately does not create user-owned home ancestors
as root. On Deeley it already exists from the manual pilot.

The publisher subprocess drops UID/GID and all supplementary groups; it verifies
it has no permitted/effective/ambient capabilities. Root supplies only read-only
FDs for completed bundle files. Publication therefore does not perform root writes
through user-controlled Dropbox paths. New files are mode 0600, directories 0700;
`.incoming-*` becomes a completed snapshot only after hash checks and fsync.
Dropbox may upload partial staging files; only final `snapshot-*` directories count.

**Backups are deliberately plaintext private Dropbox data.** They can contain
private code, prompts and reports. Dropbox access/deletion is a trust boundary;
this is neither encryption nor immutable storage. A completed local copy does not
prove upload. Periodically download from dropbox.com and compare all checksums.

## Deployment and operation

Enable the module in the reviewed NixOS configuration, build/check it and inspect
the system diff, then manually switch. No agent gets deployment privileges.
This change has not performed that switch.

Fish-compatible commands after activation:

```fish
sudo systemctl start remote-zettel-work-backup.service
sudo systemctl status remote-zettel-work-backup.service --no-pager
systemctl list-timers remote-zettel-work-backup.timer
sudo python3 -m json.tool /var/backups/remote-zettel-work/status.json
```

Status contains `attempted`, a result (`running`, `completed:<name>`, `skipped-busy`,
`skipped-admission-race`, `skipped-services-inactive`, `failed`, or `interrupted`),
and `lastCompleted`. A successful oneshot is inactive after finishing; do not
interpret that alone as failure. Missing directory conditions can skip service
startup before Python runs; inspect unit condition results if status is stale.
General journal output contains generic status only. Detailed exceptions, if any,
are root-private in `last-error.txt`; do not paste unrestricted private diagnostic
files into chat. They are not included in exported bundles.

If recovery fails, do not remove `recovery.json` or delete store locks. Inspect the
record and unit states. Starting the backup service retries recorded recovery
before attempting any new snapshot. `ExecStopPost` also retries recovery on exit.
An in-progress attempt killed by systemd is recorded as `interrupted` while its
last completed backup is retained. A same-service second start is serialized by
systemd; a separate invocation is fenced by the stable lock file.

## Recovery procedure (manual; full-service restore not yet live-tested)

1. Select a completed snapshot and download it into a separate private directory.
   Run `sha256sum -c SHA256SUMS` there. Preserve current state before any replacement.
2. Inspect archive paths/types first. **Never blindly extract over `/` or follow
   retained absolute operation aliases in a test restore.** Use a root-private
   disposable VM or separate root tree with no live mounts. Validate the manifest
   and SQLite there. Links may be retained in the archive without being materialized
   during an integrity test.
3. Reconstruct the compatible pinned application/system configuration using the
   operator's deployment repository and recorded generation/settings. Nix store
   references in metadata are evidence, not a substitute for keeping deployment
   configuration; old store paths may have been garbage-collected.
4. Disable queueing and stop web, proxy, host and executor supervisor. Confirm no
   surviving command processes. Restore all coordinator/host/executor stores from
   **one** snapshot with the matching source/documents; never restore an older
   admission ledger over newer live execution. Reconcile external document edits
   separately. Verify numeric UID/GID mapping, ACLs, source ownership and profile
   bindings before placing data at its final paths.
5. Recreate operation aliases only after validating their targets against restored
   workspaces at final paths. Do not use model-writable Git configuration as root
   commands. Do not delete ledger/lock files to bypass recovery errors.
6. Credentials are absent by design: use the dedicated interactive
   `sudo remote-zettel-work-login` while the host is stopped. Never copy callbacks
   or tokens into configuration or backup metadata.
7. Start the services with queueing disabled, inspect recovery/terminal receipts
   and task documents, then separately approve execution. A Markdown restore alone
   must never reauthorize work. Keep an out-of-band terminal available.

## Verification

```sh
python3 tests/work-backup.py
nix build --no-link path:.#checks.x86_64-linux.work-backup \
  path:.#checks.x86_64-linux.work-backup-vm
nix flake check path:.
```

Python coverage includes idle/race handling, service recovery, failed publication,
credential exclusions, retained links, ACLs when supported by the build filesystem,
SQLite WAL, corrupt snapshots, destination safety and capture process-group timeout.
The NixOS VM unconditionally verifies archived ACLs, real service lifecycle,
unprivileged replication, busy skips, failed capture recovery and SIGKILL recovery
including durable interrupted status. The full flake check includes Deeley's build.
