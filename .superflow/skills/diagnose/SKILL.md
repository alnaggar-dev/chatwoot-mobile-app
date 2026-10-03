---
name: diagnose
description: Takes every bug and performance regression: reproduce the user's actual symptom, fix it, rerun the original trigger, get one final review, and hand the exact trigger to ship. /flow routes bugs here.
---

# Diagnose

Read `CONTEXT.md` first.

**Servers (staging, production): look, don't touch.** Read logs, config, container status and plainly read-only queries. Anything that changes a server (writes, restarts, deploys, migrations, instrumentation, a one-off script or console command not plainly read-only) needs the operator's yes for that exact command.

1. **Make a loop.** A fast, repeatable pass/fail signal for the specific symptom: a failing test at a seam that reaches the bug, a replayed payload, a script against the local app (the **Run app** command, driven as in `verify` steps 2–5), a `git bisect run` harness. Flaky → raise the reproduction rate. No loop possible → stop, list what you tried, and ask for access, an artifact or permission to instrument.
2. **Reproduce** the failure the **user** described, not a nearby one, across runs. Capture the exact symptom, the minimal trigger and the failing output.
3. **Hypothesize.** Rank falsifiable hypotheses ("if X, then changing Y makes it vanish"); show the list without waiting.
4. **Instrument** one variable at a time. Every debug log carries `[DEBUG-<id>]` (e.g. `[DEBUG-a4f2]`); `ship` greps for it. Performance: baseline first, then bisect.
5. **Fix** with `tdd` where a seam reaches the bug: the trigger becomes the first failing test. No correct seam → say so; that is a finding.
6. **Rerun the original trigger.** The un-minimized loop from step 1 passes; keep that output.
7. **Clean up.** No `[DEBUG-` left; throwaway scripts deleted. Missing seam → suggest `refactor`. New terms → `CONTEXT.md`; a non-obvious decision → offer an ADR (format: `.superflow/skills/formats/ADR.md`).
8. **Summary.** Nothing is committed or staged. Write `$(git rev-parse --git-dir)/diagnose-summary` (one there for another fix → ask before overwriting; no, because that fix has not shipped and is still in the tree → stop: `/ship` it first, so two changes never mix in one review): the symptom; the exact trigger as the loop proved it (the literal input, e.g. `"a\r\n\r\n"`, never a paraphrase); the loop command; the failing-before and passing-after output pasted verbatim; the winning hypothesis; the seam or its absence. Every secret in it is written as `<redacted>`; the trigger stays otherwise literal.
9. **Review.** One `final-review` in Bug mode with the summary file, `git diff HEAD`, the untracked new files (`git ls-files -o --exclude-standard`), in a fork install `.superflow/bin/ownership.sh --changed`, and `rule://code-conventions`. Replace any earlier review block at the summary's end with `Reviewed: <.superflow/bin/fingerprint.sh>`, `Patch-id: <.superflow/bin/proof.sh patch-id>`, then its answer. `.superflow/bin/proof.sh verdict <summary> --fingerprint`: 0 → done; 3 (malformed) → rerun `final-review` once, a second 3 → stop and ask, never approval; 4 (no review block for the current code) → the review does not count: never edit `Reviewed:` to make it pass; rerun the loop, update the summary, then a fresh review; 1 → fix, rerun the loop, update the summary, review once more; still Critical or Important → stop and ask.

End: "Next: `/ship`."
