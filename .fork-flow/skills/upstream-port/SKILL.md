---
name: upstream-port
description: Merge the next upstream release into the trunk through a port/<date> branch — resolve conflicts, regenerate, probe the ledger's tripwires, journal, then land the exact SHA CI tested. Also dry-runs a port and reverts or reapplies a landed one.
disable-model-invocation: true
---

Merge one upstream release (a tag matching **Release tags** on `<upstream>`, never an unreleased development branch; oldest first; never cherry-picked) into a `port/<date>` branch cut from `origin/<trunk>`, then land the SHA CI tested. `<trunk>` is never rewritten. Stop only to ask, saying where the port stands. `<trunk>`, `<upstream>` and every bold key are read from `.omp/rules/commands.md`; a step whose key is `none` is skipped, a missing or placeholder key is asked for once.

Arguments: `[target=<tag|<upstream>|sha>] [dry-run [base=<rev>]]`, or `revert <N|sha>`. `target` defaults to the oldest release not yet merged.

Routes, first match wins:

- `dry-run` → `.fork/port-dry-run.sh [target=..] [base=..]`; report what it prints (exit 4: `./.fork/setup.sh --check` or the **Port preflight** command failed, report its message; a reapply alone it reports as needing the operator's yes). It changes nothing.
- any `refs/heads/port/*` or `origin/port/*` → resume: step 1 runs `.fork/port-status.sh` first.
- `revert` argument, a `port/revert-*` branch, or an unmatched `port-reverted:` line → `REVERT.md`.

Hard guardrails: never commit on or push to `<trunk>` except step 10's SHA-bound land; never rebase it; never force-push; never squash-merge; never `gh pr merge` a port; never `git reset --hard`, `git stash drop`, or `git checkout -- <file>` outside a merge (during one, `git checkout --theirs|--ours|-m <file>` takes a side or restores a conflict, and `git checkout -- <path>` restores the staged version); never `--no-verify` without the user's say-so. `FORK_FLOW_PORT=1` prefixes every command that commits upstream's code on a port branch: the merge and its commit, a revert and its `--continue`, the reapply-alone commit, a catch-up merge and its commit. The hook reads it from the command that commits and refuses, without it, a merge or revert commit and any commit on a port branch before its port commit (a clean `git revert` runs no hook). Fix commits of fork code (step 8, a red CI run) run without it.

## 1. Map

Resume check first: `.fork/port-status.sh`. Exit 3 → no port branch, go on. Exit 1 → read its message (fetch, `gh`, or `gh repo set-default --view` not origin's repository), fix it, rerun. Else it found one (`refs/heads/port/` or `refs/remotes/origin/port/`) and prints `branch:`, `state:`, `next:` (and `pointer=`, `target=`, `tag=` once a release merge or port commit exists; `tag=` is `<tag>` below, empty → `target`'s short SHA): not checked out → run the `git switch <branch>` it prints, then go on at `next:`. Never cut a second port while one exists. While resuming: never a second `port: upstream` commit; in a catch-up merge `pointer`/`target` come from the port commit (it prints them), never `MERGE_HEAD`; `port/revert-*` → `REVERT.md`; red CI → fix commit without `FORK_FLOW_PORT`, rerun the failing checks locally, push; landed → only step 10's cleanup, skip what is gone. Abandon, only on the operator's word: `git merge --abort` or `git revert --abort`, `git switch <trunk>`, delete the branch locally (`git branch -D`) and on origin.

`git status --porcelain` must be empty, else stop (unrelated work would ride into the port commit). `gh repo set-default --view` must print the fork's repository (`origin`'s; with two remotes `gh` may pick upstream's repo). Then `.fork/port-map.sh [target=..]` (it fetches `origin` and upstream's tags): it prints `pointer=`, `target=` (the oldest release not merged), `tag=`, the backlog and `pending-reapply=`. Exit 3 → no release to merge: `pending-reapply=none` → stop, else the reapply below; exit 1 → read its message and stop. A later target it prints as `requested: <x>` only with the operator's yes. `<tag>` below is the tag, or the short SHA of a SHA target.

Pending reapply: a `port-reverted: <revert sha>` line with no later `port-reapplied: <revert sha>` (`grep -nE '^port-(reverted|reapplied): ' .fork/PORTS.md`). Empty backlog, nothing pending → stop. Empty backlog, reapply pending (port-map exit 3) → ask the operator whether to reapply the release just reverted; yes → the port is the reapply alone, with the reverted port's range (`REVERT.md`); no → stop. With a newer release the reapply rides along (step 3), no yes needed.

`./.fork/setup.sh --check` must pass (`core.hooksPath` = `.fork/hooks`, `merge.ours.driver` unset, rerere on with `autoUpdate` off, the mergiraf driver: without it a merge gives several times the conflicts, silently; fix: `./.fork/setup.sh`), then the **Port preflight** command (toolchain, installed dependencies).

## 2. Branch

`git switch --no-track -c port/<date> origin/<trunk>` (tracking `<trunk>`, a bare `git push` offers `HEAD:<trunk>`). `<trunk>` is the backup; nothing touches it until step 10.

## 3. Merge

A pending reapply → follow `REVERT.md` before the merge, unless the branch has it (`git log --grep='This reverts commit <revert sha>' origin/<trunk>..HEAD`): git counts a reverted release as merged and never brings its code back by itself. `FORK_FLOW_PORT=1 git revert --no-edit <revert sha>` (conflict → resolve, `FORK_FLOW_PORT=1 git revert --continue --no-edit`); note it for the journal. Then:

```sh
FORK_FLOW_PORT=1 git -c rerere.autoUpdate=false -c merge.ours.driver=true merge --no-ff --no-commit "$target"
```

Keep its output: rerere's `Resolved '<path>' using previous resolution.` lines are step 4's replay list. The reapply alone runs `FORK_FLOW_PORT=1 git revert --no-commit <revert sha>` instead of both.

## 4. Resolve conflicts

List: `git -c core.quotePath=false diff --name-only --diff-filter=U`.

- **Rerere replays** stay unstaged. The replay list is only the paths step 3's `Resolved '<path>' …` lines name; after a resume every unstaged conflicted path counts as unreviewed. Never derive it as unmerged paths minus `git rerere remaining`: a binary conflict is missing from `remaining` without any replay, and `git diff` C-quotes a non-ASCII name rerere prints raw. Read each replayed file before staging it, never bulk `git add`. Replayed binaries are byte-checked. Bad replay → `git rerere forget <file> && git checkout -m <file>`.
- **Lockfiles**: `git checkout --theirs`; once the dependency manifests resolve, the **Install deps** command (then, since an install can re-point `core.hooksPath`, `./.fork/setup.sh --check`, and if it fails `./.fork/setup.sh`), then the **Regenerate lockfiles** command (install first: a lock step can fail on uninstalled dependencies), then check the fork's own dependency pins survived.
- **Other files**: read both sides. Upstream's: `git log --oneline $pointer..$target -- <file>`; a subject's `(#N)` is its PR, `gh pr view <N> -R <upstream repository>` for anything structural. The fork's: its ledger entry, `git log --grep='^Fork-Flow-Change: <slug>$' -- <file>`, and every fork commit on the file, trailered or not (`git log --oneline $pointer..origin/<trunk> -- <file>`); many fork hunks may predate the trailer.
  - Sides that do not fight (independent additions, a rename, formatting) → resolve yourself.
  - Upstream redesigned what a customization changes → carry the customization onto the new design; never drop fork behavior silently.
  - Intent unclear, or upstream may already have the fix → ask, one question per file: Keep mine / Take upstream / Keep both / Drop mine, upstream has it / Explain. Drop mine → delete or trim that ledger entry in the same resolution, or its Verify blocks step 7.
- A conflicted file in no entry's Files → add it to the right entry (Files and Tripwire paths) in step 8's fix commit.
- **Generated files** (the paths **Regenerate generated files** names): never hand-merge; `git checkout --theirs`, regenerated below.
- **Many conflicts**: group by area, one subagent per group; review every result before staging.
- **Migration collisions**, before the generated files, when **Migration versions** is not `none`: `<Migration versions> | sort | uniq -d` prints nothing (no two migrations share a version). A collision → renumber the incoming upstream migration, never a fork migration production already ran, and record the rename in a ledger entry (Files: both names; Tripwire paths: upstream's; its Verify names the new file). A duplicate version breaks the regeneration.
- **Generated files last**, once they are the only unmerged paths (no file the app loads, like config or a dependency manifest, may hold markers: the regeneration would fail on it) and dependencies are installed: `git checkout --theirs <path>`, then that path's command from **Regenerate generated files** (a generator that reads the upstream base takes `pointer` mid-merge, but `target` in a reapply alone, whose history still holds the reverted merge), then revert generator churn the port did not cause. It fails → `git checkout -- <paths it half-wrote>` (the staged versions), `git checkout --theirs <path>`, fix the cause, rerun.

## 5. Stage

A regeneration rewrote a dependency manifest → the **Install deps** and **Regenerate lockfiles** commands again, then `./.fork/setup.sh --check`, and if it fails `./.fork/setup.sh` (an install can re-point `core.hooksPath`). Then the **Post-port step** command, when the merge needs it before the checks (such as migrations).

Stage from git, not tool output (generators print partial lists): review and stage every path `git -c core.quotePath=false diff --name-only` lists. Then `git diff --quiet` passes and `git ls-files -o --exclude-standard` prints nothing: step 1 started clean, so every change is the port's, and the Verifies read the working tree while the commit takes the index.

## 6. Checks before commit

- **Clean merges**: for each customization upstream's diff touches, read the fork's callers and any stateful UI flow around it (a customization can lose behavior without a conflict).
- **Silent surfaces**: upstream's diff for every path **Silent surfaces** lists; anything the deploy needs (the **Post-port step** included) goes into the journal and the PR body, so `ship` sees it.
- **Incoming migrations**: read each migration upstream's diff adds or changes (`git diff --name-status $pointer $target` over the migration files) under `AGENTS.md`'s schema rule: the serving version keeps working on the new schema. One that drops or renames what the serving version uses → stop and ask before the push: it needs an explicit plan (the land puts it on `<trunk>`, and the next deploy runs it). Only right after the operator's yes, write the plan and `Plan agreed: "<the operator's words, quoted>" (<YYYY-MM-DD>)` into the journal's deploy notes and the PR body's `## Deploy notes`.
- **`AGENTS.md`**: pinned `merge=ours` for the release merge, which holds only under `-c merge.ours.driver=true`: the key is deliberately absent from git config (`./.fork/setup.sh --check` fails if set), so other merges, step 10's catch-up included, text-merge it, and upstream's `AGENTS.md` changes reach the fork only through this step. `git diff $pointer $target -- AGENTS.md`; empty → `agents-md: none`. Else `grep -n 'agents-md:' .fork/PORTS.md` for earlier verdicts, then one verdict per upstream rule in the journal's words (`adopted` / `rejected` / `covered`). Adopted → `.omp/rules/code-conventions.md`, committed with the journal.

## 7. Commit

`.fork/port-letin.sh $pointer $target` lists staged paths outside upstream's diff, each with its candidate kind (`lockfile`, `generated`, `ledger`, `verify program`, or `other`). Each may stay only as a lockfile, a generated file or its generator churn, an incoming migration step 4 renumbered with its ledger update, a ledger edit, or a Verify program or support file (such as `scripts/verify-*`) of an entry this resolution touched (the hook runs every Verify, so such fixes belong in the port commit). Journal each with why. `other` → judge it: generator churn or a renumbered migration may stay; anything else, or a kind that does not hold for that path, is a customization: `fork-change`, after the merge. Recheck `git diff --quiet` after any later fix. Then `./.fork/setup.sh --check`, and if it fails `./.fork/setup.sh` (a dependency install can re-point `core.hooksPath`, leaving the commit ungated). Then `FORK_FLOW_PORT=1 git commit -m 'port: upstream <tag>'` (reapply alone: `port: reapply upstream <tag>`, the reverted merge's SHA in the body). The hook runs `check.sh`. No pointer file, no trailer: the merge commit records the release.

## 8. Tripwires

Probe the ledger (`.fork/tripwires.sh`; exit 2 → it did not run, fix and rerun):

- `.fork/tripwires.sh hits $pointer $target` → the disturbed entries and their hits; an entry it does not print is untouched.
- `.fork/tripwires.sh moved $pointer $target`: a Files or Tripwire path upstream renamed (it prints the new path) or deleted → update the entry.
- `.fork/tripwires.sh paths $target`: a miss (typo, rename) → fix the entry.
- `.fork/tripwires.sh unregistered <port> $target`, `<port>` = the port commit (`port: upstream <tag>` or `port: reapply upstream <tag>`: `git log -1 -E --format=%H --grep='^port: (reapply )?upstream ' origin/<trunk>..HEAD`), HEAD only right after step 7: lists paths the fork's delta gained outside every Files since the previous port; each goes into the right entry (generator churn: the entry that owns the generator).
- `.fork/tripwires.sh unchanged $target` → retirement candidates, journaled.

Hits → one read-only `scout` per disturbed entry, all in one batch, given the entry verbatim and the hits: each Must still be true line HOLDS or BROKEN with file and symbol, and whether a Markdown doc in its Files is now wrong. Broken and mechanical → fix in a new commit (code, doc, entry), `custom(port): adapt <what> to upstream <tag>` with a `Fork-Flow-Change: <slug>` line per touched entry. Intent in question → ask.

Run each disturbed entry's Check (`.fork/check.sh --check <slug>…`), one suite at a time: never two suites on one test database.

## 9. Journal

One `.fork/PORTS.md` entry, shaped as its header says: range, conflicts and each resolution, the files step 7 let in and why, ledger verdicts, retirement candidates, `agents-md:` verdicts, deploy notes, a `port-reapplied: <revert sha>` line for a reapply, follow-ups. Commit it with any `code-conventions.md` edit: `chore(fork-flow): journal port upstream <tag>`. Every planned commit lands before the push: each pushed `port/*` revision costs a full CI run. A red-CI fix is still a new commit.

## 10. Push and land

Push once (`git push -u origin HEAD`); open the PR to `<trunk>` titled `chore: port upstream <tag>` (a conventional title check wants a conventional type; `port:` and `custom:` fail). Body: a user-facing paragraph of the release's visible changes; `## Deploy notes` (from the journal: migrations, settings, env); `## How to test` (2–5 browser or HTTP probes of the release's user-visible changes; `ship` step 6 runs them on **Deploy URL**). The full suite must run on it: **Full suite in CI** `add label <x>` → add that label; `none` → run the **Full suite (local)** command before landing. Wait for every check, `registry-gate` included (a ruleset may refuse a push whose SHA lacks it). Land by SHA: **Deploy** `automatic on merge` with **Promote** `none` → item 1's push is the production deploy: before it, `ship` step 8's migration check on `<sha>`, then ask "Push to `<trunk>` now? This deploys production." quoting the sha, the full-suite result and those migrations. No → stop: the PR stays open, nothing landed.

1. `.fork/port-land.sh <N>`: checks every check's latest run passed (SUCCESS, NEUTRAL or SKIPPED, `registry-gate` among them) and, unless **Full suite in CI** is `none`, that every full-suite check its second value names ran and succeeded (skipped or missing is not green) on the PR head, and that the local head equals it; pushes `<sha>:refs/heads/<trunk>` (never force, never `gh pr merge`), waits until the PR shows `MERGED` (a port branch deleted first can leave it `CLOSED`), fast-forwards `<trunk>`, deletes the port branch, prints "Production: run `/ship <N>`" (it watches the automatic deploy, or runs **Deploy** / **Promote** with their own approval). Tell the operator that line; never run it. Exit 3 → item 2. If a land stopped partway, rerun it: a MERGED PR whose head is on `origin/<trunk>` gets only the cleanup. Any other failure → read its message and stop.
2. `<trunk>` moved: `FORK_FLOW_PORT=1 git merge --no-edit origin/<trunk>` (no `-c` flag, so `AGENTS.md` text-merges; conflict → resolve, rerun step 7's checks against `origin/<trunk>`, not `HEAD`: `git diff --cached --name-only --no-renames origin/<trunk>`; `FORK_FLOW_PORT=1 git commit --no-edit`), push, wait, back to 1.

## 11. Report

Seven lines at most: range, conflicts auto-resolved and decided, ledger entries held / fixed / asked, checks run, PR and landed SHA.
