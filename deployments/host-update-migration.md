# Host updates and enrolled Work policy

Status (2026-11-19): host/Work migration completed successfully. Running and
selected system are now `wl48jjx...`; Work is active, the application is healthy at
`ba35e579`, and no failed systemd units were observed. Final journal commissioning
and refreshed-host activation completed successfully. Automatic deployment and its
status proxy are active, and the recovery-hold condition passes. Earlier failure,
reconciliation and preparation details in this document are historical.

## Original failure

The 2026-11-19 unrestricted `nix flake update` changed nixpkgs from `f1e5c35`
to `3457b69`. Work source pins stayed fixed, but Node, Python, ingestion policy,
service definitions and the `agent-approval-v1` writer bundle changed. The active
upgrade receipt binds the old bundle exactly. `Execution upgrade is not active`
is the target bundle's receipt mismatch, not evidence that Work needs initializing.
The running Work upgrade service reports success. Never rewrite that receipt to
accept the new bundle.

The proposed deployment controller configuration also changed while retaining its
journal directory. That journal currently has no supported policy migration.
Fixing only the first pre-switch check would leave another policy conflict.

The failed rebuild selected the proposed system profile, while `/run/current-system`
still selects the old running system. Profile selection alone does not establish
the bootloader default. Inspect both and the actual boot entries before rebooting.
Do not blindly roll back a generation or restore an old database over later work.

## Installer safeguard

`./install.sh --check` builds the exact target without changing the lock, compares
the publicly available running and target Work/controller metadata, and reports
known policy conflicts without sudo or selecting a system profile.
`./install.sh` performs the same preflight, then invokes `nixos-rebuild switch
--store-path` on that exact built target. A temporary GC root retains it through
activation. Existing privileged pre-switch checks remain authoritative.

This is an early diagnostic, not a migration or a full drain/activation rehearsal.
It deliberately leaves explicit fresh-epoch transitions to their privileged
checks. It cannot inspect protected journals, detect every repository/publication
policy conflict, prevent concurrent operator changes, or make a multi-service
activation atomic. A failure after preflight can still leave profile selection
different from the running system. Direct `nixos-rebuild` calls bypass this helper.

For application-only maintenance, update `remote-zettel` alone and run the helper.
Compare the desired application revision with automatic publication/deployment
outcomes first; a stale manual lock can select an older application.
Host/toolchain updates require the transition below. Temporarily restoring the
previous nixpkgs pin is a way to build the previous policy, not that transition.

## Selected direction: migrate policy with host updates

The operator selected explicit migration with host updates, rather than keeping
Work on a separate indefinitely pinned toolchain. The dedicated host operator below implements a fresh-board transition; the installer
safeguard detects incompatible updates and does not perform that transition.

1. **Plan from exact generations.** Build the target first. Capture immutable old
   and new contracts for stories, software Work, publication, ingestion, deployment
   controller and bridge. Report policy changes separately from application changes.
   Bind the plan to source/target generations and a digest. Reject unrelated path,
   identity, repository or authority changes unless specifically supported.
2. **Quiesce all owners.** Acquire one host-update lock, coordinate with backups,
   hold automatic delivery, and close admissions using supported controls. Check
   both Work instances, executors, preparation, ingestion, publication and controller
   journals for unsettled work. Running processes/jobs and ambiguous publication or
   activation outcomes must be reconciled before proceeding. Stop drained writers
   and verify restart fences before taking a consistent backup.
3. **Prepare durable migration receipts.** Verify backup integrity and retain the
   exact old closure. Every migrated store needs an explicit old/new policy edge
   and idempotent replay under the same plan digest. Preserve source identity,
   credentials, documents, publication history and completed deployment receipts.
   Unknown or conflicting state must stop without resetting authority.
4. **Implement the missing transitions.** The current fresh-board upgrade helper
   authorizes an explicit predecessor epoch; it does not authorize replacing an
   already activated same-epoch writer bundle. Choose a supported fresh epoch or
   implement a dedicated same-epoch drained toolchain migration. Software instance
   policy markers and controller/delivery journals also need explicit transitions.
   Existing reviews/approvals must not silently gain authority under new checks;
   retain them as history and require fresh evidence where policy changes.
5. **Advance the automatic deployment host.** Regenerate and validate the captured
   host/input graph and trusted adapter/controller configuration as part of this
   same transition. Otherwise a later automatic application release can select
   an older host configuration. Reconcile the current published/running app revision
   so the host update itself does not unintentionally downgrade the app.
6. **Activate and resume.** Only after preparation succeeds, select the exact new
   system and activate in the recorded order. Verify both repository policies,
   serving revision, runtime owners and deployment controller before reopening
   admissions and delivery. Resume interrupted steps from durable receipts; do not
   automatically restore an old lifecycle history after new work has executed.

Required evidence: a NixOS VM rehearsal using the production services and a real
nixpkgs/toolchain change; both Work repositories; old-review authority rejection;
busy-state refusal before fencing; interruption/replay at each durable boundary;
controller journal migration; and two successive automatic app releases after the
host update proving that the new host configuration stays selected.

## Self-deployment status

The live deployment bridge was observed active/running on 2026-11-19. The controller
is an on-demand unit and was inactive with a successful result. This establishes
installed/running wiring, not that an approved release completed deployment.
The prior rollout document still calls initial commissioning/activation the next
step; inspect protected journals and retained release outcomes before treating
that section as a current instruction to initialize them again.

## Reconciliation operator prepared on 2026-11-19

`scripts/reconcile-host-profile.py` is deliberately bound to the exact running
`jczv8zy...` and failed `4b1j492...` generations observed above. It is not a general
rollback command. The immutable, GC-rooted copy is:
`/nix/store/ydzarggxri7k6ikq1nxdgd3cj22jl3g5-reconcile-host-profile.py`.
Run it with the running generation's Python, `sudo`, and `-I`.
The operator executed reconciliation successfully. Independent profile reads now
show both selections at the source generation, and the operator supplied `bootctl`
output identifying generation 156 as the default entry with that exact init path.
The bridge is observed inactive/dead with a successful result. Sudo remains
unavailable noninteractively to the agent.

It validates terminal deployment/delivery receipts against the running controller
policy, creates a protected recovery hold, signals only the bridge main process
for graceful drain, and acquires its controller and delivery ownership locks.
Unsettled/uncertain state or a drain timeout refuses profile selection. It checks
the current Work guard before selecting the exact running generation and running
that generation's `boot` action to refresh boot configuration. Work/application
services are not switched and no application database is restored. Durable
maintenance receipts live under `/var/lib/remote-zettel-host-maintenance`.
The operator hold remains in place for migration. Inspect the printed boot entries
and actual profile selections after execution; preparation is not completion.

The read-only `scripts/plan-host-policy-migration.py TARGET` captures immutable
old/new generation, stories enrollment, software enrollment/state policy,
controller/bridge metadata and unit hashes. It refuses unrelated identity, path,
model and repository changes. The generated plan explicitly grants no activation
authority. The current plan and GC roots for both systems are retained under
`.local/host-policy-migration/`.

Further source inspection found that the executor supervisor explicitly rejects
retained candidate-check/review profile history under a different policy. Updating
only a host ledger profile or instance marker cannot migrate that history.
An explicit store-generation/history transition is needed. The proposed target's
bridge publication enrollment also still pins the old publication/check policy,
although software execution checks changed. Publication must be reconciled as part
of migration rather than leaving this mixed enrollment in service.

## Fresh-board transition selected

The operator explicitly selected fresh boards with retained Previous boards for
host updates. Both stories and software histories must be exported as inert
read-only history before changing their live board pointers. Prior approvals and
publication/deployment receipts retain only their original audit meaning.

The Remote Zettel working tree now has optional software-instance `epoch`
namespaces, inherited publication endpoint namespaces, and self-deployment
`stateGeneration` journal namespaces. Static accounts/UIDs/GIDs remain unchanged.
The global deployment recovery hold is deliberately independent of the new
controller state directory. Three focused Nix module checks and nine instance-state
checks passed. These namespace changes are now pinned into Deeley and activated by the recorded
first-stage operator.

The bounded read-only protected-state inventory is frozen at
`/nix/store/06jgrwlg34lrdc5xrk11nz5w7i6sd2fa-deeley-policy-inventory/inspect-host-policy-state.py`.
It uses the sibling immutable planner module, emits only allowlisted counts/status
metadata and publication policy records, and excludes credential stores, model
output and task text. This observation is not a globally consistent backup, proof
of runtime drain or migration authority. The operator supplied its output: both Work hosts and executor ledgers are terminal
or settled, publication reservations and incomplete publication slots are zero, and
controller/delivery journals are empty. These observations are rechecked under
ownership and restart fences by the migration operator.

Source policy binds its runtime implementation location and bytes. The transition
needs a fresh verified source copy/pin at the preserved advancing base as well as
fresh worker, publisher and deployment roots. Merely reusing the original source
pin with a new toolchain can fail its implementation binding. The final automatic
deployment host must be captured after these policy values are commissioned.

## Prepared host-20261119 transition

The user approved fresh boards for both repositories, retaining old boards as
inert Previous boards. The target uses nixpkgs `3457b69`, fresh Work/publication/
source roots, and the dedicated `host-20261119` epoch. Account IDs, SSH destination,
trust, and protected key references are preserved. The immutable source snapshot
is `/nix/store/a7wjp19i03dhwhnlfd5h3kmzm18xlgfi-remote-zettel-host-policy-source`.
It includes the working tree changes required for this migration; it is not a
published upstream revision.

The first activation deliberately disables automatic deployment. Its old journals
are retained and independently verified in a private snapshot. It does not rebind
old deployment receipts to the new controller policy. After this activation,
commission the fresh controller/delivery namespace from the protected public
publication policy, refresh the captured trusted host graph, verify application
revision invariance, and resume delivery only after checking the final generation.

The root operator is built separately from the target to avoid a dependency cycle.
It binds the exact reconciled source generation and recovery-hold SHA256, drains
both repositories and deployment journals, acquires existing ownership locks,
fences old services, stops drained owners, and snapshots the old state before
retirement. Snapshot validation independently reopens the selected archived SQLite
files with their WAL/rollback state. Login databases use a separate protected
handoff and are excluded from historical snapshots; SSH keys are referenced in
place and are never copied into Nix inputs or history.

Preparation exports both old boards, copies and verifies both source repositories
at their retained advancing bases, commissions fresh policies, and persists
manifest-bound receipts. Only then does it select and switch to its exact target.
It checks both fresh boards and all required services after activation. Runtime
fences and the global recovery hold persist after uncertainty; repeat only the
same immutable operator to resume. Do not initialize an old store, rewrite policy
receipts, run a generic rollback, or remove masks to get past a failed stage.

Verification passed: the combined two-repository NixOS rehearsal, three Nix module
checks, the software-source commissioning VM, host Work/policy invariance checks,
and the focused Python/Node suites. The combined rehearsal covers both old
publication histories, busy-state refusal before fencing, independently verified
snapshots, fresh policies, native switching, Previous boards, replay, and new
software execution after switching and restarting services. Its result is retained
at `/nix/store/qkpyxgkha05rribcp0mcmqb0nc64j1al-vm-test-run-work-host-toolchain-upgrade`.
The rehearsal uses synthetic identities and one fixture toolchain; the actual
built Deeley target additionally passes immutable predecessor, complete-closure,
and transport comparisons. This does not establish two live automatic releases
or qualify the hardware bootloader.

The reviewed operator and exact target are GC-rooted under
`.local/host-policy-migration/`. Run the immutable operator in a terminal:

```sh
sudo /nix/store/5pncgmmggr3ghdyj5ckkcy5aq4a4dhcs-migrate-host-policy/bin/migrate-host-policy
```

This switches the host and fresh Work policies, with a brief web-service outage.
The user executed this operator successfully. Running and selected generation now
match `ybvf0ab...`, and Work and application health were independently verified.
Automatic deployment stays held for the second commissioning stage.

After successful first activation the operator prints the public policy path:
`/var/lib/remote-zettel-host-upgrade-public/host-20261119/publication.json`.
Private receipts and software/deployment snapshots are under
`/var/lib/remote-zettel-host-upgrades/host-20261119`; the primary transition manifest
identifies its own protected receipt/snapshot directory. The global recovery hold
remains `/var/lib/remote-zettel-self-deployment/operator-recovery`.

## Final deployment resume prepared

The freshly commissioned public policy has been copied into
`deployments/remote-zettel-publication.json`. The updated trusted host is retained
at `/nix/store/20asjjrn4gxbmvl57hgz6smxzy0ah21h-deeley-trusted-deployment-host`.
Normal and restricted builds both select
`/nix/store/wl48jjx8mbyr0vj8wliyh2vijs4s7z85-nixos-system-deeley-26.05.20261118.3457b69`.
Both Work transition manifests and the generation contract are byte-for-byte
unchanged from the first-stage host. The application revision stays `ba35e579`.
Two application revision variants retain identical controller/publication/Work
commands and policies. No live application publication/deployment was manufactured.

The journal initializer commissions both fresh journals in private staging
locations, seals their file inventories, and only then renames each directory into
its reserved final namespace. Replay reuses sealed journals and preserves the first
rename after interruption; unrelated directories and changed installed journals
are refused. A failed unsealed attempt remains private and is not installed or
reset. Five integration checks with the real controller/outbox implementations
pass in a disposable root VM. Old journal records are never copied or rebound.

The reviewed immutable resume command is:

```sh
sudo /nix/store/6fl3a3q1mkqq6hpgq3zmkcjji35zfyqv-resume-host-deployment/bin/resume-host-deployment
```

It validates the completed first-stage receipt, protected publication policy,
current/selected host and unchanged Work manifests; installs the new empty policy-
bound journals; switches to the exact final host while the existing hold gates
bridge startup; verifies Work and the application revision against the serving
MainPID; and removes only the exact recorded recovery hold before starting the
bridge. Its release intent and completion receipts live under
`/var/lib/remote-zettel-host-upgrades/host-20261119/deployment-resume`.
An interrupted or failed attempt never resets journals or silently removes a
changed hold. Reuse this exact operator to resume, and inspect its receipts before
manual intervention if later automatic work has already advanced the generation.

The initial controller has no automatic-deployment history, so deployment status
may report `no-running-evidence` until the first approved automatic release. The
operator separately verifies the live application; it does not forge a deployment
receipt to populate that history. Two successive real approved app releases remain
an end-to-end validation step through the normal Work approval flow.

For a future reviewed host capture, first archive the input graph, run
`scripts/capture-remote-zettel-deployment-inputs.py ARCHIVE_JSON deployment/inputs.nix`,
and build `path:.#capture-deployment-host`. The capture script also emits
`deployment/captured-sources.json`; the package retains every captured source as a
Nix dependency, allowing the fixed builder's restricted evaluation. This helper
reproduces the exact trusted host directory used here. Replacing its pin changes
controller policy and still requires a reviewed transition, rather than an
ordinary app update.

### Readiness correction after final activation

The initial resume operator installed both journals and activated `wl48jjx...`,
then stopped when its single Work CLI board probe failed immediately after the
web restart. The application subsequently reports healthy at `ba35e579`, both
system selections match the final target, no failed systemd units were observed,
and the bridge remains inactive with its hold condition unsatisfied.

The corrected operator above retains the exact same immutable plan
`/nix/store/nfcpyq11k193s1zkr92xd4869ikfwy56-resume-host-deployment-plan.json`.
It reuses the installed journals and receipts, waiting up to 30 seconds for the
read-only Work board probe. Each attempt is bounded to five seconds, runs from
`/`, and terminates its subprocess group on timeout. Wrong repository enrollment
is refused. Only the read-only board query is retried; Work mutations are never
replayed. Regression checks cover delayed socket creation, CLI failure before
readiness, bounded failure, foreign enrollment, inherited working-directory
independence and cleanup of a hung probe. Existing journal replay checks still
pass. The recovery hold is released only after board and process-bound HTTP health
checks pass. The first immutable resume operator remains retained under
`.local/host-policy-migration/resume-operator-initial` for audit.

## Completion verified

The user ran the corrected resume operator successfully. Independent checks show
running and selected system both at `wl48jjx...`; web, Work upgrade, deployment
bridge and deployment-status proxy active; no failed units; and HTTP health at
`ba35e5799dcfe1cc2914ba6e992d62ec9cdda627`. The bridge's condition passes and its
result is success. The reported commissioned controller policy is
`09f5d995cb010fbcb2c13dc82ec7a42cae9b9671f5efcdc085beacb44fee9b54`.

The final `./install.sh --check` also passes and selects the exact settled system.
The migration and deployment resumption are complete. No synthetic release or
deployment receipt was created. Real approved application releases still provide
the end-to-end deployment evidence; completion of maintenance is not a claim that
two such releases have been tested. Repository changes remain uncommitted, and
the reviewed runtime source is retained by its immutable store pin and GC roots.
