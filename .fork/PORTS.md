# Upstream Port Journal

Short memory for the next port, not a diary. `upstream-port` step 9 appends one entry per release merge, written by hand and committed on the port branch before the push; a port revert and a reapply get one too. Git's ancestry records which releases are in; this journal records why each decision went the way it did.

A release-merge entry, headed `## <date> — port upstream <tag> (<pointer>..<target>)`, records:

- Conflicts: each file and how it was resolved (rerere replays reviewed, the side taken, fork behavior carried onto upstream's redesign, what the operator decided).
- Let in: every file outside upstream's diff that step 7 allowed into the merge commit, and why.
- Ledger: a verdict per disturbed entry (HOLDS, fixed in `<sha>`, asked), entries updated for renames or unregistered files; retirement candidates.
- `agents-md:` one line per upstream `AGENTS.md` rule, `agents-md: adopted|rejected|covered — <rule in ≤12 words> — <why>`, or `agents-md: none`. Grep this file for earlier verdicts before judging a rule again.
- Deploy: what `ship` must know (the post-port step, silent-surface changes such as feature flags, env, config, runtime versions), or none.
- Follow-ups.

Step 1 greps for two lines, each written at the start of a line. A revert entry (`upstream-port revert`) carries `port-reverted: <revert sha>` with the tag and why; the port that reapplies it carries `port-reapplied: <revert sha>`, the same full SHA (step 1 matches the text). A `port-reverted` line with no later matching `port-reapplied` line means the next port reapplies that release first.

<!-- Example:
## 2026-10-14 — port upstream v2.3.0 (9f920b549c..4c1d2e3f5a)

Conflicts (3):
  - package-lock.json — upstream's side, regenerated with the Regenerate lockfiles command; the fork's pins survived
  - src/jobs/response_builder.ts — upstream split normalization into a helper; the fork's extra field now travels inside it (rich-replies)
  - schema.sql — upstream's side, regenerated with the Regenerate generated files command
Let in: none
Ledger: rich-replies HOLDS; login-banner fixed in 5e6f7a8b9c; retirement candidate: hide-build-info
agents-md: none
Deploy: one migration, adds an index; new optional env var RESPONSE_TIMEOUT
Follow-ups: none
-->

---
