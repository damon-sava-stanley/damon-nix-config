# Deeley Work pilot: prepared, queueing disabled

The configuration pins Remote Zettel to
`a07a6894b2df9dd8a7875e9764314e058f8b222a` and prepares the private stories pilot:

- `workPilot.enable = true`
- **`workPilot.enableExecution = false`**
- Documents: `/home/damon/Dropbox/agent-workspace`
- Captured stories base: `bb48c49b1ddeba9a8f6934b505d553dafbf9094b`
- Checks: `test -d drafts && git diff --check` (structural/whitespace checks only)

No source fetch, publisher, automatic task execution or general main-agent shell
is enabled. The old npm dependency-hash override was removed because this release
contains the corrected upstream hash.

## Verification, 2026-10-31

`nix flake check -L` passed, including the full Deeley system build and the new
`work-pilot` assertions. The new check first failed on the previous release pin.
Only the Remote Zettel lock node changed; all other locked dependencies remained
unchanged. An independent review found no substantive issues.

Compared with the running system:

- Both use Nixpkgs `08d3a97586f6b6343b3b5e799980773629432610` and the exact same
  Linux 6.18.59 kernel store path.
- Added host, proxy, supervisor and two executor unit templates.
- The web unit adds the Work document mount, document/state configuration and
  frontend socket group, and updates the application executable.
- **No `WORK_PI_ENROLLMENT` is present in the web environment.** Simulation is
  also disabled; Work will initially be a document-only board.
- Existing unit-content changes are limited to `remote-zettel.service`,
  `mandb.service` and `systemd-tmpfiles-resetup.service`. The latter two are derived
  from the added package/manual environment and tmpfiles configuration.
- No package-version/kernel downgrade or desktop change was shown by the system
  closure comparison.

Reviewed candidate:

`/nix/store/kj6chiscwzp0rr5lb3yqnijyzirfshgy-nixos-system-deeley-26.05.20261028.08d3a97`

Running system at review time:

`/nix/store/jvy9ms5r5zh816013ycfnrcf7d74i734-nixos-system-deeley-26.05.20261028.08d3a97`

**This candidate has not been activated.** Builds and checks do not create live
service identities, grant ACLs or provision credentials. The candidate is retained
through `/home/damon/.local/share/remote-zettel-pilot/prepared-system`.

## Before switching

The clean operator-owned source was prepared separately, leaving the existing
personal checkout and its writing untouched:

`/home/damon/.local/share/remote-zettel-pilot/stories-fjebnhf1/source`

It has the exact base above and no remote or symlink entries. It is not yet the
required root-owned source at `/var/lib/remote-zettel-work-source`. Provision that
in the operator's sudo terminal using the upstream runbook. Refuse an existing
destination rather than replacing it; verify the base, root ownership, mode 0700
on the root directory, no non-root/group/other writers and no symlinks.

The document directory exists, but Dropbox sync/restore remains unverified.
Back up any existing operational state before activation. Review this configuration
and the system diff before explicitly approving a switch; no switch command has
been executed by the assistant.

After the approved manual switch, use the interactive
`sudo remote-zettel-work-login` command and start/check the host. Never paste OAuth
callbacks or credentials into chat. Verify effective permissions, Access rejection,
owner task access, Dropbox recovery and backups before separately approving
queueing for a tiny live smoke.

The host/proxy/supervisor units are enabled even though queueing is disabled.
The host is skipped without its credential file; the supervisor refuses an absent
or unsafe source. Preparing services is not equivalent to cancelling active work.

Full operator runbook:
https://github.com/damon-sava-stanley/remote-zettel/blob/a07a6894b2df9dd8a7875e9764314e058f8b222a/docs/work-production-pilot.md

The new `work-pilot` check deliberately asserts `enableExecution = false` and the
approved release/base. A later separately approved queueing or profile change must
update that check explicitly, not work around it.
