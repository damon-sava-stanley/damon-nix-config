# Note checkpoint gate release — 2026-10-31

Status: operator activated the configuration; live process/settings checks passed.
**Live smoke complete:** chat creation/edit, recovery, stopped-bridge write denial,
restart/retry, and disposable-note cleanup all passed.

## Live verification after activation

- Active system: `/nix/store/bbhazjwx1fq1gan5v2v0zi9lyycya3hj-nixos-system-deeley-26.05.20261028.08d3a97`.
  This differs from the earlier candidate path below; the running application
  executable matches the reviewed checkpoint release.
- Web process uses `/nix/store/1q516zbi79m7n051257xklzzypyv1p8i-remote-zettel-0.1.0/bin/remote-zettel`.
- Both checkpoint environment settings match the configured socket and host root.
- The running web process's effective groups include `zettel-checkpoint`.
- Bridge runs as `damon`, with socket directory 0750 and socket 0660.
- Live mountinfo confirms `/home` read-only, notes read-only, and backup state writable
  inside the bridge namespace. PrivateNetwork is enabled.
- A request from the owner UID (`damon`, not the authorized web UID) was rejected.
- Periodic timer is active, and its latest local checkpoint was successfully pushed.

These checks do not substitute for a successful authorized web-tool request, note
recovery test, or stopped-bridge denial smoke. No note contents were read or modified
as part of this verification.

## Successful chat smoke and recovery

Interactive chat created `notes/2026-10-31t155201-check-point-smoke-test.md` and
edited its body from `Check Point Smoke version 1` to `Checkpoint Smoke version 2`.
Both revisions were exported into a separate temporary directory and verified;
the temporary recovery copies were removed without modifying the live note.

- Create checkpoint: `a63284e4b3330a5601f172b41f9c5eb26286ee7d`.
- Edit checkpoint: `a7cbb215e9a7097eb8d937f993b4720fa5211be0`.
- GitHub main matched the edit checkpoint at verification.
- Live note matched the edit checkpoint exactly; pre-denial-test SHA-256:
  `a914664ebc1e6d79e6cf7547893f69ae016f1e5219a6a3df06c9d494e37c10e2`.

With the bridge stopped, chat reported that the pre-write checkpoint failed twice.
The live note's SHA-256 remained exactly the pre-test value above: neither attempt
changed it. The bridge was confirmed inactive and the periodic backup timer active.
After restarting the bridge, chat successfully wrote version 3. The live note
matched checkpoint `456aba14a4cf2fcc870175342824b87be351a4e3` exactly. Cleanup
verified that exact file hash before deleting only the disposable note. Deletion
checkpoint `20a6415272a5ae19945b5481948c3d6d61f19fc6` was pushed successfully;
version 3 remains recoverable from history. The bridge and periodic timer are active.

## Release and build

- Application: `56e33577549b7039fd88b4b4782fffe2db0cd81d`, published to Remote Zettel main.
- Only the `remote-zettel` flake input was updated; Nixpkgs and other inputs unchanged.
- Deeley enables `services.zettel-checkpoint-bridge.enable` and configures
  `services.remote-zettel.noteCheckpointSocket` together.
- Work pilot execution remains disabled; no publisher or broad Bash tools added.
- Live baseline when built: `/nix/store/2qbsbjlxcg11divmn241k1xs90lr5vmf-nixos-system-deeley-26.05.20261028.08d3a97`.
- Built candidate: `/nix/store/9hmhkb6ag7mx3srvhdy231mywvx4gl7n-nixos-system-deeley-26.05.20261028.08d3a97`.
- Candidate GC root: `~/.local/state/zettel-checkpoint/release-system`.
- `nix store diff-closures` shows the updated app and checkpoint bridge, with no
  Nixpkgs/kernel change. Web unit diff adds the checkpoint socket/root environment
  and replaces the application executable; its existing filesystem hardening remains.

Verified: TypeScript and all 313 app tests; app Nix module; note-checkpoint,
note-checkpoint-bridge, note-checkpoint-bridge-vm and Work preparation checks;
full host flake evaluation and full system build. The private backup state and notes
exist; existing web service and periodic backup timer were active before handoff.

## Activate in the operator terminal

From the reviewed checkout:

```sh
sudo nixos-rebuild switch --flake /home/damon/workspace/damon-nix-config#deeley
systemctl status remote-zettel.service zettel-checkpoint-bridge.service --no-pager
systemctl --user status zettel-checkpoint.timer --no-pager
```

The sudo password belongs only in the operator terminal, never chat. Do not activate
additional unreviewed changes. A successful build alone does not establish effective
live identities/mounts or model-mediated gating.

## Required post-activation smoke

1. Confirm the web executable is the published release, both NOTE_CHECKPOINT variables
   are present, the web process has the socket group, and the bridge is active.
2. Verify the web identity can request a checkpoint but cannot read private history
   or SSH credentials, and the bridge sees notes read-only. Do not dump note contents
   or credentials into general logs/chat.
3. Create one clearly named disposable note through interactive chat, then edit it.
   Verify Git contains recoverable pre-edit and post-edit versions and ordinary
   periodic pushes still succeed. No broad tool expansion is needed.
4. While no other writes are running, stop the bridge and attempt a disposable edit.
   Confirm the tool reports pre-checkpoint failure and the note is unchanged.
   Restart the bridge promptly and confirm a later edit succeeds.
5. Delete only the disposable test note after verification and checkpoint the deletion.
   Restore/export tests must use a separate directory, not reset the live Dropbox tree.

No model task or note mutation was performed as part of build preparation. UI health,
background/manual writes and whole-prompt cancellation remain follow-up work. If the
bridge fails, interactive create/edit fail closed; repair it rather than silently
removing the gate. The periodic user backup remains a separate service.
