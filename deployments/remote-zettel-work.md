# Remote Zettel Work enrollment

Run from your normal user in an interactive terminal:

```sh
./scripts/enroll-remote-zettel
```

The launcher snapshots the tracked and unignored working files from this repository,
builds its `enroll-remote-zettel` package, and then requests sudo. It uses
`deployments/remote-zettel-work.lock`, the input pins validated against the existing
stories enrollment. Pending changes in the regular `flake.lock` are preserved.
The working Home Manager configuration is included, as in a normal host rebuild.
Ignored files, Git metadata and previous build results are excluded from the snapshot.

The immutable operator package:

1. Commissions a fresh protected offline source, or verifies the existing source
   against its independently retained policy pin. Partial or conflicting state is
   retained and rejected.
2. Activates `nixosConfigurations.deeley-work-preparation` when authentication is
   needed, waits for preparation, and verifies the exact instance policy.
3. Runs the dedicated login interactively. Callback codes stay in the terminal.
   An interrupted login with an empty credential store can resume; lost previously
   installed credentials or policy drift require explicit operator recovery.
4. Activates `nixosConfigurations.deeley`, waits for all five runtime services,
   and verifies both the shared board and the repository catalog.

It stops on the first failing operation. On switch failure it reports the selected
profile and actual running system, rather than continuing to catalog calls. It
never bypasses pre-switch checks or attempts automatic rollback. Re-running the
same command resumes completed steps without recommissioning authority or repeating
successful login. Concurrent invocations are rejected by a root-owned lock.

`hosts/deeley/remote-zettel-software.nix` is the permanent declaration. Execution
is enabled in the default Deeley configuration; preparation is an `extendModules`
variant of that same configuration. Future builds therefore retain the repository
instead of relying on a temporary configuration outside this checkout.

The software module/runtime/source inputs are independently pinned. The two local
immutable snapshot inputs are existing reviewed provisioning artifacts, retained
through the deployed system closure. The software check policy adds the locked
Even SDK, reaps exited orphan test descendants, excludes nested fixture tests and
runs the native reading-list tests with Node. The prior full-repository acceptance
passed 183 Vitest files / 2,151 assertions and two native tests under the production
2 GiB, 128-task and 1,200-second limits.

The normal lock currently contains other pending input updates. Do not mix those
into this enrollment: Work binds toolchain/package and service PATH identities.
Review future deployment-input changes in `deployments/remote-zettel-work.lock`
and use the supported policy transition when those identities change. Keeping the
reviewed lock separate preserves the pending changes without rebinding live stories
or the new software policy during bootstrap.

Operator progress is kept under `/var/lib/remote-zettel-software-enrollment`.
The existing instance marker, source authority, credential journal and histories
are never deleted or recreated as recovery. The launcher does not queue model
work, initialize publication authority, publish or enable automatic deployment.

The first supervised Work task should remove the tracked root `result` symlink
and add `/result` to `.gitignore`. Candidate preparation requires regular files;
the removal path has passed capture and immutable preparation for all 889 files.
Publication commissioning follows successful execution and retained check/review
evidence.

Validation:

```sh
nix build --reference-lock-file deployments/remote-zettel-work.lock --no-write-lock-file \
  .#checks.x86_64-linux.remote-zettel-enrollment \
  .#checks.x86_64-linux.remote-zettel-source \
  .#checks.x86_64-linux.work-pilot
```

New files must be tracked before using Git-flake `.#` syntax. The enrollment launcher
also includes unignored new files, so it can bootstrap this working tree directly.
