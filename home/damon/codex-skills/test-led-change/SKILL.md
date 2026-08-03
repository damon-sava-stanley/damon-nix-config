---
name: test-led-change
description: Plan and implement non-trivial repository changes using a short
  change brief, acceptance-test-first development, and optional ADRs.
---

For non-trivial behavioural changes:

1. Create `docs/changes/<change>.md` from the change-brief template.
2. Keep the brief concise. Capture:
   - the problem and desired outcome;
   - scope and explicit non-goals;
   - a high-level design sketch;
   - representative acceptance examples;
   - risks and unresolved questions.
3. Before implementation, convert the first acceptance example into a
   failing automated test and demonstrate that it fails for the expected reason.
4. Implement one vertical slice at a time using red-green-refactor.
5. Treat tests as the source of truth for observable behaviour.
6. Record a separate ADR *only* for an architecturally significant decision.
7. Before completion:
   - run focused and full test suites;
   - reconcile the brief with what was actually built;
   - remove resolved questions;
   - delete the active brief. 
