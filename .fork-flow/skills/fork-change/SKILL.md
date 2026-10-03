---
name: fork-change
description: Commit the working-tree change with its .fork/CHANGES.md entry in one trailered commit (honesty check, Verify proof, checks); `retire <slug>` removes a customization. Run by `ship` step 3; never pushes.
argument-hint: "[retire <slug>]  — commits the working tree on the current branch; never pushes"
disable-model-invocation: true
---

Routes: `retire <slug>` argument, or step 3 finds the change removes a customization → `RETIRE.md`. `<trunk>` and `<upstream>` are the **Trunk** and **Upstream** values in `.omp/rules/commands.md`.

Guardrails: the current task branch; never push; never `git stash`, `git reset`, `git checkout -- <file>` or `git commit --amend`; never `--no-verify` unless the user says so. Base: `b=$(git merge-base HEAD <upstream>)`; failure → stop.

## 1. Read the change

`git add -A`, then `git diff --cached --stat` and the diff of each file. Every path must belong to this change. Anything that does not, even legitimate unrelated work, and anything that looks accidental (secrets, build output, big binaries) → ask; on the answer, `git restore --staged <path>` keeps it out.

## 2. Integration point

Check against `AGENTS.md` Fork rules → **Customizations**. Deviation → say so and prefer redoing it.

## 3. Place it in the ledger

Shape: the `.fork/CHANGES.md` preamble. Match changed files against every entry's Files. A file under several entries → pick the entry by what the change is for, not by the file. Existing entry → update its fields (fork-owned files of the change may go in its Files). None fits and the change touches an upstream-owned file → new entry; a change to fork-owned files only needs no entry. The change removes a customization → delete its entry and follow `RETIRE.md`. One change may touch several entries. Every Tripwire path written must match a file at the base: `.fork/tripwires.sh paths "$b" <slugs written>` prints nothing.

## 4. Honesty check

Every changed upstream-owned file is in at least one entry's Files. Exempt: `.fork/CHANGES.md`, `.fork/PORTS.md`, changelogs; every fork-owned file (the base lacks it: the kit folders, `docs/adr/`, the fork's own code, scripts and docs), added, changed or deleted; files restored to upstream's version (`git diff --quiet "$b" -- <file>` succeeds: no fork delta left, as when step 3 deleted their entry). A shared file is listed under every entry that changes it, so the tripwire probe watches it for each; a new entry that edits one adds it to its own Files.

```sh
git add -- <each path step 3 wrote>   # the ledger, a new Verify program: honest.sh reads the index
.fork/honest.sh --cached
```

It lists changed upstream-owned paths no Files matches (`--no-renames` keeps a moved file's upstream path): exit 1 while it lists any, 0 silent, 2 it did not run (fix and rerun). Fix the ledger until it prints nothing.

Work landed without an entry: run this on a branch with no code change. Step 3 writes the entry; this step finds its commits (those the operator names, and `git log --no-merges --format='%h %s' "$b"..HEAD -- <its Files>`) and checks each one's full path list (`.fork/honest.sh <sha>^ <sha>` each), not only the staged ledger; step 8 commits the ledger alone with the trailer.

## 5. Prove a new or changed Verify

A Verify that reads a file first asserts it exists, so absence fails on that assertion, not on a missing input (a Verify on a script: exists, then a syntax check). A silent failure gets an assertion message first.

Prove it in throwaway worktrees: name every program the Verify runs that the base lacks or has in an older version, and the data they read (such as `scripts/verify-*`). Never name the customization itself, even when the Verify reads it.

- **Base**: `.fork/prove-verify.sh base <slug> <programs, data>` must fail, naming this entry's own assertion; any other failure proves nothing. A nonzero exit alone is never proof: a missing interpreter script usually exits 1, not 127. A missing program or data file, or "could not run", proves nothing.
- **Pre-change `HEAD`**, when the change adds or changes the behavior asserted: `.fork/prove-verify.sh head <slug> <programs, data>` must fail too; never required for a backfill. A checker-only addition that asserts nothing new (a self-test flag added to a Verify) passes there by design: break the condition it checks in the worktree and watch it fail. Skip for a ledger-only commit of committed work.
- **Working tree**: `.fork/check.sh <slug>` passes.

## 6. Checks

`.fork/check.sh` and `.fork/check.sh --check <touched entries that still exist>`. A failure I caused → fix. Unrelated → note it in the commit body.

## 7. Docs

A touched entry's Files include a Markdown doc (`docs/*.md`, `CONTEXT.md`, …) and this change alters what it describes → update it, rather than adding a new doc. A new feature doc from `document` is just another changed file for step 4; when step 3 chose an entry, add the doc to its Files, and add its "registered as" line and Verification map naming the entry if missing; when it chose none, the doc names no entry.

## 8. Commit

Stage by name every path steps 3–7 wrote or repaired (ledger, docs, code fixes, Verify programs and data); never `git add -A` again, so what step 1 left out stays out. `git diff --quiet -- <every path step 1 staged or steps 3–7 wrote>` must pass: the checks read the working tree, the commit takes the index. A path changed after step 6 → rerun step 6.

```sh
git commit -m "custom(<area>): <what changed>" -m "<one sentence>" -m "Fork-Flow-Change: <slug>
Fork-Flow-Change: <each other touched slug>"
```

Conventional Commits, no AI-assistant attribution: a customization's subject is `custom(<area>): …`, any other change takes its conventional type (`feat`, `fix`, `chore`, `docs`, …); if the project lints commit messages (commitlint `type-enum` or similar), `custom` and `port` must be allowed types. The trailer block is the last paragraph (a trailer inside the body is not parsed; the `commit-msg` hook refuses a commit without one). No entry touched still gets one, so `ship` never folds it as WIP: `Fork-Flow-Change: superflow-workflow` when only kit folders changed, `Fork-Flow-Change: none` for any other change that touches no entry (fork-owned files only, ADRs, changelogs, `.fork/PORTS.md`).

## 9. Report

Three lines: what was committed, which entries, which checks ran.
