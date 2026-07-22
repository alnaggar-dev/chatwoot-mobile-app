<!-- BEGIN fork-flow:memory — managed block; re-run the kit installer to update. Keep your own notes OUTSIDE these markers (they are overwritten on update). -->
# Fork Maintenance

This repo is a **personal fork**. Your customizations live on `custom/main` and must survive upstream changes. You never merge upstream — you integrate it **one commit at a time**, porting each upstream commit onto your fork, tracked by `.fork/UPSTREAM` (the SHA of the last upstream commit you ported). Four skills drive the work: **`fork-change`** (register a customization), **`upstream-port`** (port upstream), **`drop-change`** (retire a customization), **`propose-upstream`** (send a change to the author) — each lives at `.fork-flow/skills/<name>/SKILL.md`. Read `.fork/CHANGES.md` before changing code or porting.

## Hard rules

- **Never `git pull upstream` or `git merge upstream`.** Fetch, inspect each commit, then **port** it with `./.fork/port.sh` — it cherry-picks `-x --no-commit`, advances `.fork/UPSTREAM` in the *same* commit, and writes a `Fork-Flow-Port: <sha>` trailer (that trailer, not the staged pointer, is what the gate and `audit.sh` trust). Don't hand-roll the cherry-pick.
- **Lowest-risk integration point wins:** upstream extension point > net-new file you own > small in-place edit > `merge=ours` whole-file override (last resort — it hides upstream changes, including security fixes). This is the one choice you make *while* coding.
- **Register every customization** in `.fork/CHANGES.md`, in the *same* `custom:` commit (the `commit-msg` hook warns, never blocks, if you forget). End that commit message with `Fork-Flow-Change: <slug>` (the heading's slug) so `drop-change`/`propose-upstream` can find its commits exactly.
- **`./.fork/verify.sh` is the gate.** It builds/tests and runs every registry entry's `Verify`, proving your customizations survived; the `pre-commit` hook runs it (`--registry`) on any commit that integrates upstream **or stages `.fork/CHANGES.md`** — registering and retiring are gated too (bypass: `--no-verify`). During a `port.sh run` batch each port's gate is SCOPED to the entries that commit touches, and the batch end re-runs the FULL registry plus touched entries' `Test:` (`--scoped`). The shipped CI workflow (`.github/workflows/fork-flow-gate.yml`) re-runs the FULL gate on every push to `custom/main` (repo variable `FORK_FLOW_CI_GATE=registry` narrows it) — the server-side backstop that earns the fast scoped local runs (enable Actions on the fork once).
- **Port small and often** (stop at release tags), and **prune** with `./.fork/audit.sh` — the cheapest customization is one you can delete (the `drop-change` skill retires one cleanly).
- **Lockfiles are never hand-merged.** `port.sh` run/range auto-resolve a conflicted lockfile (upstream's side + the ecosystem's own re-resolve, staged and journaled); doing it by hand (opted out or unsupported ecosystem): take upstream's side, re-run the install so your own dependencies re-resolve on top, stage, continue. The user-extensible `.fork/REGEN` table applies the same take-theirs + regenerate + stage flow to other generated files; its commands are project-controlled code (the same trust class as a registry `Verify`) and it is disabled together with lockfile auto-resolve.
- **One writer.** This flow assumes a single linear `custom/main` written from one clone at a time — porting from two machines (or letting a bot commit) diverges it with no sanctioned reconcile. Serialize ports through one clone; other clones only `git pull --ff-only`.

## Adding a customization → run the `fork-change` skill

Code the change first, at the lowest-risk integration point (above). Then run `fork-change` before committing: it reads your diff, drafts the `.fork/CHANGES.md` entry, and runs the gate. Commit code and entry together in one `custom:` commit.

## Porting from upstream → run the `upstream-port` skill

Run `upstream-port` (driven by `./.fork/port.sh`). Once on a fresh fork: `./.fork/port.sh init <sha> [ref]`. Then `./.fork/port.sh plan` forecasts the backlog (per commit: clean / empty / conflict(files) / +flag(registry entries)) and `./.fork/port.sh run` batches it — clean picks port straight through (each still its own trailered, gated commit); the loop PAUSES on a real conflict or a clean pick touching registry entries. At a conflict: inspect with `./.fork/conflict-context.sh <sha> <file>`, re-apply your customization onto upstream's new code, `git add`, `./.fork/port.sh continue`, then `run` again (the batch resumes; its end runs the scoped verify and journals one fact entry in `.fork/PORTS.md`). Never silently take upstream and drop a custom behavior. `next` still single-steps. Undo the newest port with `./.fork/port.sh revert` — it rewinds `.fork/UPSTREAM` and re-runs the gate, and `next`/`run` can re-port later. **Fell releases behind?** Catch up per release: `./.fork/port.sh plan --range <release-tag>` forecasts, then `./.fork/port.sh range <release-tag>` runs the same merge machinery as per-commit ports (native conflicts and merge drivers) as the primary catch-up unit; use per-commit `run` for small backlogs or bisection.

For a multi-machine-safe landing, port on `port/<date>`, push it, open a PR to `custom/main`, and after CI run `./.fork/port.sh land`: it binds the tested SHA and uses a non-force push. The direct-push flow remains valid for a solo clone.

For an urgent security fix out of order, use `./.fork/port.sh pick <sha>`: it leaves the pointer unchanged; register the picked customization immediately, with the upstream commit named in `Reason`, so the later normal port can land empty.

## Retiring a customization → run the `drop-change` skill

When upstream ships your change (audit's patch-id hits, your merged PR) or you no longer want one, run `drop-change`: it reverts the customization's commit(s) and deletes its `.fork/CHANGES.md` entry in the same `custom: retire <slug>` commit — the `pre-commit` gate fires on that commit automatically (a staged registry change is a gate trigger) and proves every remaining entry still passes. Retire BEFORE porting the upstream commit that ships the same change, so that port applies clean. Audit's DROP CANDIDATES list is this skill's worklist.

## Proposing a change upstream → run the `propose-upstream` skill

When a customization is worth contributing, mark its entry `Status: proposed-upstream` and run `propose-upstream`. It derives the upstream base ref from `.fork/UPSTREAM` (never assume `upstream/main` — many projects default to `develop`) and cherry-picks only that customization's commit(s) onto it — **never merge `custom/main` into a PR**, which drags every other customization into the author's history — strips fork-flow bookkeeping, verifies in isolation, and opens the PR. Keep the entry `proposed-upstream` until upstream merges it; then retire it at the next port.

## Registry — `.fork/CHANGES.md` (one entry per customization)

Each entry starts with `## custom: <slug>` (exactly two `#`, a space, a non-empty slug — `verify.sh` fails the gate on a malformed heading so a typo can't drop the next entry's `Verify`). Fields:

- **Reason** — one sentence: why it exists.
- **Touches** — tracked file paths it depends on; `;`-separated (the field also splits on `,`, so keep prose/parenthetical notes out of it), grep-friendly.
- **Verify** — a command, or `manual: <what to look at>` (`verify.sh` runs the non-`manual:` ones; unmarked prose runs and fails). Default to a micro-runnable asserting a **value/shape** (`node -e`/`ruby -e`/`python -c` against the file — still sub-second, no install), not a grep: a grep survives relocated/disabled code; use it only when the string itself *is* the customization. For committed entries, `./.fork/verify.sh --prove <slug>` mechanically proves a watched failure by reverting its `Touches` paths to the pointer copy: `Verify` must fail without the customization and pass after restoration. The warn-only path-level delta tripwire flags entries with no remaining fork delta across `Touches` (low specificity when anchors overlap other entries), so it is a retirement signal, not proof.
- **Test** — optional; the project's own targeted test command for the customization's behavior (may take seconds, assumes a worked-in tree). `verify.sh --scoped` — run at the end of every `port.sh run` batch — executes the `Test` of each touched entry; entries without one are listed as presence-verified only.
- **Symbols** — `name@path`; add only when a same-signature upstream change could break you *silently* (derive with `lsp references`, or `search` if no language server). Symbols without a `Drift-if` is valid when no honest runtime tripwire exists.
- **Drift-if** — the condition that would silently break it; when present, `Verify` MUST be a runnable tripwire.
- **Status** — optional; `proposed-upstream` (PR open), `superseded` / `upstreamed` / `applied-upstream` (upstream has it) — all four make `audit.sh` list the entry as a DROP CANDIDATE for the `drop-change` skill.
Custom `custom:` commits MUST end with `Fork-Flow-Change: <slug>`, using the same `[A-Za-z0-9_-]` slug as the registry heading (the commit-msg hook reminds you). `drop-change`/`propose-upstream` search this trailer first for exact commits; older entries fall back to path-based archaeology.

## Layout

```
custom/main         your daily branch          custom/<slug>      larger change, squash-merged
upstream/<default>  read-only upstream mirror   pr/<slug>          clean PR branch off the upstream mirror

.fork/UPSTREAM             pointer: "<sha> <ref>" of the last upstream commit you ported
.fork/port.sh              the PORT driver: init (--force = sanctioned re-target) | list | plan [--range][--porcelain] (forecast) | next | one | pick (early security port) | run [--until][--limit][--no-lockfile-auto] (batch; pauses on conflicts/registry) | range [--no-lockfile-auto] (catch-up) | revert | land [--dry-run][--no-checks] | continue | abort | status [--porcelain]
.fork/CHANGES.md           registry (Reason, Touches, Verify, Test, Symbols, Drift-if, Status)
.fork/REGEN                generated-file rules: take upstream's side, regenerate, stage
.fork/PORTS.md             port journal (each `run` appends one fact entry; conflicted single ports/ranges auto-append a skeleton)
.fork/verify.sh            the gate — --fast | --registry [--scope f] | --scoped [--paths f] | --prove <slug> (watched-failure proof) | full (runs every Verify)
.fork/brief.sh             per-commit risk briefing (rename/delete/glob-aware)
.fork/conflict-context.sh  per-file conflict hunks + the upstream commit being ported
.fork/audit.sh             health: fork delta, merge=ours divergence, orphans, unregistered, drop candidates, unported backlog, pointer consistency
.fork/setup.sh             per-clone wiring (hooks + git config); run once per clone — --check reports
.fork-flow/skills/         the four skills (fork-change, upstream-port, drop-change, propose-upstream)
.fork/hooks/               commit-msg reminder + integration gate (pre-commit, pre-merge-commit); chains any pre-existing hook manager
.gitattributes             merge=ours overrides (last resort) + extended mergiraf syntax-aware coverage for supported code/declarative languages (ON by default); !merge unsets package-lock.json, npm-shrinkwrap.json, pnpm-lock.yaml so REGEN owns lockfiles
.github/workflows/fork-flow-gate.yml   CI gate: re-runs the FULL verify on every push (FORK_FLOW_CI_GATE=registry narrows; hooks are per-clone, CI is not)
```

Per-clone setup is one-time per clone — neither `git clone` nor copied files carry it: run `./.fork/setup.sh` (shipped with the fork; `--check` reports wiring). It sets the hooks and git config — a hook manager the project already uses (husky etc., even a dormant `.husky/` before the first install) is CHAINED, not clobbered: the gate runs first, then its hooks; managers that re-point hooks on dependency installs un-wire the kit, which `verify.sh`/`port.sh` warn about (re-run setup). Port commits run with `FORK_FLOW_PORT=1` set — guard the project's own formatter hooks on it (port.sh warns when a chained hook rewrote a port; rewritten ports stop matching upstream). Setup also configures the `mergiraf` merge driver — the `merge=mergiraf` lines in `.gitattributes` are active; when the binary is missing, setup configures Git's normal text merge as a safe fallback (install it with `cargo install mergiraf` / `brew install mergiraf`, then re-run setup to activate syntax-aware merges). First-time GitHub wiring (origin/upstream remotes + `custom/main`) is the kit installer's job: `install.sh --setup` (it applies the same setup.sh). Then set the pointer once with `./.fork/port.sh init <upstream-sha> upstream/<default-branch>` (if upstream ever force-pushes its history, the one sanctioned pointer reset is `init --force` — see the upstream-port skill; never hand-edit `.fork/UPSTREAM`).
<!-- END fork-flow:memory -->
