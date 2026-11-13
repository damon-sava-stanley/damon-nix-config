# Deeley continuation: maintained deployment pin

This is the historical continuation rollout receipt. Current application/runtime
selection and the task-lifecycle handoff are declared in `hosts/deeley/default.nix`;
see the repository README for the normal update/switch procedure.

The continuation implementation and rollout records are published in Remote Zettel.
This deployment pins `0d994f54f7c43fcc7af30bfdd2757affdb3af733` and explicitly sets
`workPilot.enableContinuation = true`, retaining the existing queueing switch.
The pilot configuration check asserts the release and continuation capability.

## Verification

Built successfully from the maintained checkout with its existing unrelated edits:

```sh
nix build path:.#nixosConfigurations.deeley.config.system.build.toplevel \
  path:.#checks.x86_64-linux.work-pilot
```

Result:
`/nix/store/ryzlmb5z0pjfki20h0jqv06ga4sd77kr-nixos-system-deeley-26.05.20261029.6f06d20`

The installed generation remains:
`/nix/store/wcg4dbss7wln8fg9ngrqabn32zd3z2ph-nixos-system-deeley-26.05.20261029.6f06d20`

The two builds have byte-identical packaged `src` and `static` trees and select the
exact same enrollment:
`/nix/store/682j8sla6xb8p4wh2vwxpnbxz0s1mvki-work-pilot-enrollment.json`.
The unit changes only reference the newly pinned package in web/host and mandb;
executor policy/paths and admission fingerprint remain unchanged. Documentation
and source-provenance differences account for the new package/system store paths.
No new ledger migration or live switch was performed for pin reconciliation.

## Live rollout evidence

The operator completed a drained policy-only host-ledger migration, queue-disabled
preparation switch, explicit queueing enablement and a successful two-run smoke:

- Parent: `8a516753-ba20-4bb8-8e26-f41e2ec2b2f9`.
- Successor: `04f5831b-dd9a-434f-88bd-a47c405755c5`.
- Post-smoke backup: `snapshot-20261031T214341Z-5762c1fu`.
- Archive SHA-256: `b33a1953a6cb6aa40843cab2bbc84a9f00dc78194b7303de170ce8b241252fe6`.

Independent local-copy checksums and saved-state checks confirmed the continuation
edge, successful receipts, retained checkout, exact two-line smoke file, drained
stores and unchanged trusted source. The backup reports 21 SQLite integrity checks.
The operator explicitly waived another Dropbox download round trip after two prior
successful tests; no new cloud download is claimed for this snapshot.

See Remote Zettel's `docs/deployments/deeley-continuation-upgrade.md` and
`docs/work-continuation-upgrade.md` for the full receipts and rollback limits.

## Working-tree scope

Only the application pin, continuation setting, corresponding release/capability
assertions and this receipt belong to the reconciliation commit. Pre-existing
power-policy, backup and other working-tree edits were preserved and not bundled.
The build above includes those existing edits because they are already part of
the approved live configuration; a clean checkout of this commit alone is not
claimed to reproduce those still-uncommitted changes. Preserve the deployed backup
fix during future reconciliation. No publication authority was added.
