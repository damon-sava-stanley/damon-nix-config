# Deeley approved application deployment

Status (2026-11-19): the original publisher and deployment journals are already
commissioned. A host update exposed incompatible Work/controller policy changes.
The selected profile and boot default were reconciled to the running generation;
the fresh-board migration, fresh-journal commissioning and refreshed-host activation
completed successfully. Automatic deployment and its status proxy are active,
the recovery-hold condition passes, and the live application is healthy.
Follow [host update migration](host-update-migration.md) for the current transition.
The initial activation section below records the original rollout and must not be
used to reinitialize existing stores.

Remote Zettel execution is enrolled beside stories. An approved, successfully
published Work candidate can be deployed automatically. The independent bridge
checks protected publication evidence, builds the exact commit, switches Deeley,
and checks both the serving process and its packaged revision. A Git push alone
does not supply this publication evidence.

The moving `remote-zettel` input remains useful for manual application updates.
Routine application releases do not change the enrolled worker, software checker,
publisher, deployment controller, host modules, or nixpkgs. The captured host in
`deployments/remote-zettel-deployment-host.nix` retains the complete input graph.
`deployment/` contains the corresponding builder, graph and resolver for review.
The builder reads application bytes through the trusted package recipe; it never
evaluates the candidate's flake or adopts its dependency locks.

The repository is private. The adapter uses the dedicated GitHub deploy key
“Deeley Remote Zettel publication” (key ID 170380971) only for the fixed source
prefetch. Its private file is `/var/lib/remote-zettel-software-publication-key/identity`,
root-owned mode 0400. Fetching disables user/system Git configuration, SSH agent
use, prompts and user SSH configuration, and uses pinned GitHub trust and address.
The build/evaluation commands receive no SSH credential environment. Candidate
builds remain inside Nix's sandbox with separate build users.

The original rollout kept the stories writer bundle and software execution policy unchanged.
The one-time source bootstrap advanced the unused software source from `15edcc2`
to `78e91bf`, retaining prior objects, source identity and explicit receipts. It
refuses task documents, observed task history, runs, identity conflicts, unknown
partial state and conflicting pointers. This is not a refresh procedure for an
already-used software board.

## Initial activation

Build and commission the delivery/controller journals once, then switch:

```sh
nix build path:.#initialize-remote-zettel-deployment --out-link .local/self-deployment-initialize
sudo .local/self-deployment-initialize/bin/initialize-remote-zettel-deployment
./install.sh
```

Initialization creates the protected journals without publishing, building or
activating an application release. It refuses existing or partial journals; do not
remove them to force a retry. Publisher commissioning and its original receipts
remain under `/var/lib/remote-zettel-software-publication`. Its public policy
record is copied into `deployments/remote-zettel-publication.json`.

The first Work task should remove the tracked root `result` symlink and ignore
`/result`. Review the retained checks and exact candidate, approve it through the
normal authenticated Work interface, and verify publication/deployment outcomes
and the running revision. Then repeat with a small independent application change.

## Maintenance and recovery

Use the Work approval/publication flow for automatic application deployment. For
a deliberate manual application update, update only that input before switching:

```sh
nix flake update remote-zettel
./install.sh
```

A manual switch using a stale application lock can select an older app than the
latest automatic release. Compare desired/published/running revisions first.
Do not use an unrestricted `nix flake update` as an application-update command:
toolchain changes alter the enrolled Work identities. The pending pre-repair lock
is preserved in `.local/repair-before-nixpkgs-restore.lock`.

The fixed host snapshot also fixes host/Home Manager settings for future automatic
releases. Host, dependency, runtime and controller-policy changes need a separately
reviewed transition. Existing deployment journals reject a different controller
policy; journal-policy migrations are not implemented. Changing the snapshot pin
is not itself such a transition. External Git changes after this bootstrap also
require supported source reconciliation rather than editing the advancing base.

For an uncertain activation, first create the protected recovery hold and stop
bridge delivery:

```sh
sudo touch /var/lib/remote-zettel-self-deployment/operator-recovery
sudo systemctl stop remote-zettel-deployment-bridge
```

Inspect retained deployment receipts and actual current/profile selections. Use
the pinned controller's observation/reconciliation procedure; never reset its
journal or blindly replay activation. Complete recovery with the web offline if
necessary, then remove the hold and explicitly start delivery. Automatic rollback
is not provided. The detailed controller/adapter procedures are in Remote Zettel's
`docs/work-nixos-deployment.md` and `docs/work-deployment-controller.md`.

Validation includes the real-schema, initially-account-free publication bootstrap
VM; a synthetic private SSH/Nix source-build VM; five private-fetch boundary tests;
the host Work/Even checks; equality of normal and restricted system builds; and a
configuration check proving two application revisions preserve identical controller,
publication and execution policy while selecting different application packages.

## First real application release after migration

Migration fixes were pushed to Remote Zettel as `b3e28ada2f80a1978bf2a5b7ba005a78c9ee0588`.
The migrated software source still points at `78e91bf`; before creating the first
new software task, the exact reviewed fast-forward is supplied by
`packages.x86_64-linux.test-app-release`. It retains a byte/hash-bound pack and uses
the existing before-first-task bootstrap primitive. It refuses software task or
publication history, acquires maintenance/ownership guards, drains automatic
delivery, fences admissions and stops drained software owners, advances the exact
source pointers, verifies the unchanged enrollment, and restores services. Neither
credentials nor historical journals are copied or rebound. A root VM verifies the
source-policy fingerprint and pointer replay, including existing-task refusal.

After source restoration it imports one deterministic task document as the
application UID, without overwriting user edits, and queues its first run through
the existing Work control API. The task requests only removal of the tracked root
`result` symlink and addition of `/result` to `.gitignore`. Its ID is
`66e4db62-4bb4-437b-bdb8-5b43d0b66c3a`. No synthetic approval or deployment record
is created. Queue uncertainty is inspected through the existing board rather than
blindly replayed. The worker and trusted independent checks/review produce the
candidate through their normal services.

The software publication policy requires a genuine Cloudflare Access human
approval. Open `https://zettel.ss-damon.com/#work`, select the software task, review
its exact candidate/check/review snapshot and approve through the normal UI.
Chat approval is not substituted for that enrolled identity, and no JWT is copied
or manufactured by the test operator.

A temporary observer runs as the application UID, with private networking and
restricted filesystem writes. It queries only the Work board, approval history and
read-only deployment-status proxy. It exports allowlisted IDs, statuses and commit
metadata to `/var/lib/remote-zettel-app-release-test-observer/status.json`; no task
text, credential material or approval token is exported. This file is a progress
projection, not deployment authority. The observer stops after associated successful
publication/deployment or two hours. Final verification independently compares the
remote commit, protected advancing base, current/selected generation, immutable
packaged revision, serving health and unchanged Work/controller contracts.
