---
name: refactor
description: Find and apply deepening refactors in the project's own code (a fork's own code in a fork install), using CONTEXT.md and docs/adr/. Use when the user wants to improve architecture, consolidate coupled modules, or make code easier to test. Ends with one final review; leaves the work uncommitted for ship.
disable-model-invocation: true
---

# Refactor

Turn shallow modules into deep ones: much behavior behind a small interface.

Scope: any of the project's own code; vendored, generated and third-party code is called, never reshaped. In a fork install (`.fork/CHANGES.md` exists), **fork-owned code only** (`AGENTS.md` → Fork rules → **Ownership**): `.superflow/bin/ownership.sh <each path you restructure>` must print `fork-owned`; `upstream-owned` → call that code, never restructure it; exit 2 → stop.

Terms:
- **Interface**: everything a caller must know (types, invariants, ordering, error modes, config). **Seam**: where it lives. **Adapter**: what fills a seam.
- **Deletion test**: delete the module in your head. Complexity vanishes → pass-through. It reappears across callers → it earns its keep.
- **The interface is the test surface.** A test that breaks when the implementation changes tests past it.
- **One adapter is a hypothetical seam, two a real one.** No port without two (usually production and test).

## Steps
1. **Context.** Read `CONTEXT.md`; treat it and the ADRs as claims: where code disagrees, show it and ask which to fix.
2. **Explore** the code in scope, weighted to recent changes (`git log -n 50 --name-only`). Friction: one concept spread over many small modules, interfaces as complex as their bodies, coupling across seams, code hard to test.
3. **Candidates.** Numbered: files, problem, solution, benefits (locality, leverage, tests), in `CONTEXT.md` terms. Raise an ADR conflict only when the friction justifies reopening it. Ask which to explore.
4. **Grill the pick.** Constraints, what goes behind the seam, which tests survive. Dependencies: in-process (merge, test directly), local stand-in (test with it), remote but owned (port + in-memory adapter), external (injected port, mock). An open interface → sketch 2–3 very different designs and recommend one.
5. **Apply.** Before the first edit, run the tests next to each path you will restructure (the **Test one file** command from `.omp/rules/commands.md`, or `.superflow/bin/near-tests.sh`) and keep the command and its output. Then a fresh `owner` (`.omp/agents/owner.md`) applies the chosen design: its task gives the design from step 4, the paths, and these rules: move complexity behind the interface, migrate callers, delete old shallow modules and their tests once the new tests cover them (replace, don't layer); adapt a caller outside the scope (an upstream, vendored or third-party one) minimally at its call site, never relocate it; near tests green after each step; no coverage → behavior tests at the new interface first; leave the work uncommitted. When it returns, review its diff yourself (`git diff HEAD` and the untracked new files) and write your own summary; never pass its report through; rerun the near tests yourself. Wrong design → step 4.
6. **Review.** Nothing is committed or staged. Write `$(git rev-parse --git-dir)/refactor-summary` (one there for another change → ask before overwriting; no, because that refactor has not shipped and is still in the tree → stop: `/ship` it first, so two changes never mix in one review): what moved behind which interface; the callers migrated; the modules and tests deleted; the near-test command with its output before and after, pasted verbatim. One `final-review` in Refactor mode with the summary file, `git diff HEAD`, the untracked new files (`git ls-files -o --exclude-standard`), in a fork install `.superflow/bin/ownership.sh --changed`, and `rule://code-conventions`. Replace any earlier review block at the summary's end with `Reviewed: <.superflow/bin/fingerprint.sh>`, `Patch-id: <.superflow/bin/proof.sh patch-id>`, then its answer. `.superflow/bin/proof.sh verdict <summary> --fingerprint`: 0 → done; 3 (malformed) → rerun `final-review` once, a second 3 → stop and ask, never approval; 4 (no review block for the current code) → the review does not count: never edit `Reviewed:` to make it pass; rerun the near tests, update the summary, then a fresh review; 1 → a fresh `owner` fixes it, rerun the near tests, update the summary, review once more; still Critical or Important → stop and ask.

Lasting decisions → an ADR (`.superflow/skills/formats/ADR.md`), including a candidate rejected for a load-bearing reason; terms → `CONTEXT.md` (`.superflow/skills/formats/CONTEXT.md`).

The work and the summary stay in the working tree for `ship`, whose step 1 checks the verdict. Close with what was applied and what is left, then: "Next: `/ship`."
