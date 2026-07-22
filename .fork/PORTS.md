# Upstream Port Journal

Short memory for the next port — not a diary. One entry per `port.sh run` batch (the script writes it), plus one per conflicted single port / `range` catch-up / conflicted revert, appended in port order. See your agent memory (`AGENTS.md`), Fork Maintenance section, for the format.

`port.sh` writes the FACTS itself, inside the run's journal commit (or the port commit for a single conflicted port/range/revert): a `run` batch appends one `## run <date> <old>..<new>` entry — commits ported (with empty and lockfile-auto-resolve counts), every pause (`paused: <sha> conflict|registry <files|entries>`), the scoped-verify result, timings — with one `Judgment: (fill in)` line per pause. Single conflicted ports and ranges keep the skeleton form (conflict list + `(fill in)` placeholders). Replace every placeholder with the real decisions (the upstream-port skill says when); even unfilled, the facts preserve the one thing nothing else records: WHICH commits needed a human decision, and why the run believed itself done. Trivial clean ports inside a batch need no lines of their own.

Each entry ends up recording: the upstream SHA(s) ported, conflicts and how they were resolved, `rerere` replays checked, drift-check verdicts (`Symbols`/`Drift-if`), lockfile auto-resolves, `merge=ours` decisions, the `verify.sh --scoped` result (CI runs the full gate on push), and any `audit.sh` follow-ups. The `.fork/UPSTREAM` pointer is the authoritative record of how far you have ported; this journal is the *why*.

<!-- Example:
## 2026-05-29 — ported upstream def5678 "Rework input layout"

Applied: git cherry-pick -x --no-commit def5678; .fork/UPSTREAM -> def5678
Conflicts: RichInput.tsx (useLayout -> useDisplayMode), re-applied horizontal layout
rerere: package.json replay checked, still correct
Drift-check: useDisplayMode orientation kept -> safe
merge=ours: none in this commit
Audit: input-mode customization superseded by an upstream setting -> removed
Verify: ./.fork/verify.sh --registry passed; full verify.sh passed at end of run
-->

---

_No upstream ports yet._
