---
name: document
description: Close out a feature before ship. Gates on the brief's final-review verdict for the current HEAD, writes the feature doc, lifts decisions into ADRs, CONTEXT.md or an issue, asks one grouped confirmation, then deletes features/<slug>/. Commits nothing.
disable-model-invocation: true
---

# Document

`/document <slug>`. `features/<slug>/PRD.md` is never committed: what this skill lifts out of it is all that survives, and deleting the folder is final. The doc, ADRs and `CONTEXT.md` ride `ship`. Touch only this branch's feature folder (or the one the operator names for an abandoned feature with no branch). The proof folder is `v=$(git rev-parse --git-dir)/superflow/<slug>/verify`.

## 1. Final-review gate
`.superflow/bin/proof.sh verdict features/<slug>/PRD.md --head` must exit 0. Otherwise stop and say why; `/flow <slug>` runs the review. Exit 4 includes uncommitted code since the review: the fix is `/flow <slug>` steps 7–8 (the brief is still there). An abandoned feature with no code skips this step (say so).

## 2. Write the feature doc
New behavior → `docs/<slug>.md` from [TEMPLATE.md](TEMPLATE.md); behavior an existing doc covers → update its sections. Abandoned feature → no doc. The template's ledger lines stay for `fork-change` to fill in a fork install (`.fork/CHANGES.md` exists); a base install drops them.
- Cite real paths, symbols and constant values from the shipped code. Can't find it → say so.
- Terse, present tense; tables, bullet rules, an ASCII flow for every branch.
- `## What it does / does NOT do` holds the brief's out-of-scope items and rejected alternatives.
- A Browser journey's Setup block comes from the values verify recorded in `$v/report.md`, not invented ones.
- No host commands, secrets or `reviewed:` markers; link the section of the project's operations docs instead of host commands.

## 3. Lift decisions
From the brief's `## Decisions` (both `Yours` and `flow's default`), `## Out of scope` and Minor findings worth keeping, take each item with value beyond the code (a rejected alternative, a deliberate no, a hidden constraint, a new domain term) and propose a home: an ADR (`.superflow/skills/formats/ADR.md`), `CONTEXT.md` (`.superflow/skills/formats/CONTEXT.md`), the feature doc, or a GitHub issue.

## 4. One grouped confirmation
One message, answered in one reply:
1. Each proposed lift and its home.
2. Unchecked `## Done when` items: delete anyway?
3. Delete `features/<slug>/`? It holds:
   ```sh
   (set -o pipefail
   git ls-files -c -- features/<slug>/ | sed 's/^/tracked   /' &&
   git ls-files -o --exclude-standard -- features/<slug>/ | sed 's/^/untracked /' &&
   git ls-files -o -i --exclude-standard -- features/<slug>/ | sed 's/^/ignored   /')
   ```
   A nonzero exit means the list is unknown: stop.
4. When `$v/report.md` exists: each item's pass or fail, and whether its `Fingerprint-after:` line matches `.superflow/bin/fingerprint.sh` now. A failed or stale report is shown; the operator decides.

## 5. Apply, then delete
Apply the approved lifts (an issue: `gh issue create`, record the URL). Delete only after the operator's yes:
```sh
git rm -r -q -f --ignore-unmatch -- features/<slug>/ && rm -rf features/<slug>/ && ! test -e features/<slug>
```
A no, or a failure, leaves the folder; report it.

Report: docs written, ADRs, `CONTEXT.md` terms, issue URL, folder deleted or not. End: "Next: `/ship`."
