<!-- BEGIN superflow (managed by the SuperFlow kit's install.sh; change the kit, not this block) -->
## Workflow (SuperFlow)

| Need | Skill |
|---|---|
| Build a feature | `/flow <request>`: brief, branch, build, prove, review; `/flow <slug>` resumes. Then `ship` |
| Vague idea → decisions | `grill` (optional; feeds `flow`) |
| Drive it in the browser | `verify` proves Done-when items in the browser or by tests (used by `flow`) |
| Docs, then the folder goes | `document` (run by `ship`) |
| Land it | `ship` |
| Any bug or perf regression | `diagnose`, then `ship` |
| Architecture pass | `refactor`, then `ship` |
| Design spike | `prototype` |

Skills without a trigger of their own (`verify`, `tdd`, `refactor`, `prototype`) start only from this table or their caller: read `skill://<name>`. The full map, kit edits included: `.superflow/WORKFLOW.md`.

- Skills live in `.omp/skills/` (links into `.superflow/skills/`); read a skill before running it. Gestures are written `/name`; omp invokes `/skill:name`. After any context compaction, re-read the active skill (`skill://<name>`) before the next write or gate.
- Project commands and facts: `.omp/rules/commands.md`, one line per key; read it before running any project command. `<trunk>` is its **Trunk** value, `<upstream>` its **Upstream** value. A key that is missing, `none` where a value is required, or still a `<…>` placeholder → ask once, never guess. Code conventions: `.omp/rules/code-conventions.md`.
- Subagents are the project agents in `.omp/agents/` (`final-review`); the model roles `task` and `senior` live in `.omp/config.yml`.
- A feature's only working file is its brief `features/<slug>/PRD.md` (git-ignored); `document` turns it into docs and ADRs, then deletes the folder. Workflow state lives under `$(git rev-parse --git-dir)/superflow/`, never in the tree.
- Decisions reserved for the operator: auth and permissions, data exposure, public API, schema. Ask; never default them. The brief records them as `Yours`, never asked again.
- One clone, one tree: one working tree per clone; no extra worktrees for feature work. Never commit on `<trunk>`; never commit secrets (`.env*`, keys, tokens).
- Schema changes stay backward-compatible: add first, remove in a later release. The old version keeps serving on the migrated schema, during the deploy and after a rollback.
- `CONTEXT.md` (the glossary: use its words, never invent synonyms) and `docs/adr/` bind. Read the area's ADRs before touching it; a change that contradicts one → say "this contradicts ADR-NNNN" and ask. Create either only when the first term or decision needs it.
- A fork install adds its own rules under `## Fork rules`; where they differ from these, Fork rules win.
<!-- END superflow -->

<!-- BEGIN superflow:fork (managed by the SuperFlow kit's install.sh; change the kit, not this block) -->
## Fork rules

This project is a fork: fork-flow keeps it in sync with upstream. This file is fork-owned: upstream's `AGENTS.md` never merges into it (`AGENTS.md merge=ours` in `.gitattributes`; `upstream-port` reads upstream's diff instead).

- **Customizations**: the default is a minimal, contiguous inline edit in the upstream file. Behavior with no upstream counterpart goes in a new fork-owned file. Hooks, extension points or overlays only when one file's inline hunk is large and re-conflicts on every port, recorded in an ADR. `merge=ours` is never used for code. Test files follow the same rule.
- **Ownership**: `.superflow/bin/ownership.sh <path>` prints `fork-owned` (free to restructure) or `upstream-owned` (inline edits only, never moved, split or restructured), judged against the upstream base `git merge-base HEAD <upstream>`.
- **Ports**: upstream releases arrive only through `upstream-port`. The **Merge method** is `merge`: never squash-merge or rebase-merge into `<trunk>`; history is the only record of which releases are in.

### Fork setup (per clone)

Remotes: `origin` is the fork, `upstream` the project it forks (`git remote add upstream <url> && git fetch --tags upstream`). Run `./.fork/setup.sh` once per clone (git config is per clone: rerere, merge drivers, `core.hooksPath .fork/hooks`, chaining a hooks dir already in use); `./.fork/setup.sh --check` reports the wiring and exits 1 when it is incomplete. The hooks refuse a commit on `<trunk>`, a commit without a `Fork-Flow-Change:` trailer (`wip:` subjects and merges exempt) and a push of `wip:` commits, and run the ledger gate `./.fork/check.sh`. To add a hook tool later (git lfs, lefthook, pre-commit): `git config --unset core.hooksPath`, run the tool's install, then `./.fork/setup.sh` again.

### Fork workflow map

| Need | Skill |
|---|---|
| Sync with upstream | `upstream-port`, then `/ship <N>` |
| Back out a bad upstream release | `upstream-port revert <N\|sha>` |
| Retire a customization | `fork-change retire <slug>` |
| Edit the workflow kit itself | change it in the SuperFlow kit and re-run its `install.sh` |

`fork-change` and `upstream-port` have no trigger of their own: they start only from this table or their caller (`ship` runs `fork-change`): read `skill://<name>`.
<!-- END superflow:fork -->
