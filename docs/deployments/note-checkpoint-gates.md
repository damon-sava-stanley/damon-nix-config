# Note checkpoint gate release — 2026-10-31

Status: reviewed release/configuration prepared and full host system built;
**live activation and disposable-note smoke pending** (interactive sudo required).

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
