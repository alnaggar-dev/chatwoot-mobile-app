---
name: flow
description: Build a feature end to end: brief, branch, build, verify, final review. /flow <request> starts; /flow <slug> resumes.
disable-model-invocation: true
---

# Flow

Copy steps 1–9 into the todo list word for word. A step you skip stays, marked `skip: <reason>`. `<trunk>` is the **Trunk** in `.omp/rules/commands.md`; the proof lives in `v=$(git rev-parse --git-dir)/superflow/<slug>/verify`, never in the tree. `/flow <slug>` with a brief already there resumes: read it and `git log --oneline origin/<trunk>..HEAD`, then continue at the first unfinished step. Step 5 runs only after the go, so a brief with no branch yet (such as one `grill` wrote) has not had it: finish steps 3–4, then show the whole brief and wait. Once `$v/report.md` exists, the proof is stale when its `Commit:` is not HEAD or `.superflow/bin/proof.sh verdict features/<slug>/PRD.md --head` exits 4 (no review for this HEAD, or uncommitted code) → step 7, unticking every item.

1. **Route.** A bug → `diagnose`. A structure-only change → `refactor`. A design question only an experiment can answer → `prototype`. A feature continues here.
2. **Grill** with `grill` when the request is vague or needs a decision `AGENTS.md` reserves for the operator. A clear, low-risk request skips it.
3. **Map and shape.** Read `CONTEXT.md`, the area's ADRs and the code the change touches. In a fork install (`.fork/CHANGES.md` exists), `.superflow/bin/ownership.sh <path>` names the upstream-owned files (**Ownership**). Name the data shape and sketch the interface callers use before writing logic.
4. **Brief.** Pick a kebab-case slug; `.superflow/bin/feature-branch.sh --check <slug>` fails → stop and ask. Write `features/<slug>/PRD.md` (format below), show it in full, and wait for the operator's go; their changes go into the brief, which is shown again. `## Out of scope` names every item of the request left out, one by one (each finding of an audit or list, never only a category), each with its reason. After the go, any change to the brief (a decision, a Done-when item, scope) is shown and needs a new go; ticking Done-when items and the `## Final review` block are not changes.
5. **Branch.** `.superflow/bin/feature-branch.sh <slug>`. It fails → stop and show its message.
6. **Build** with `tdd`, following `rule://code-conventions`. Checkpoint with `git commit -m "wip: <what>"`, never pushed, never `--no-verify`. Build leaves `docs/` alone: `document` (run by `ship`) writes and updates feature docs. A slice given to a subagent carries in its task text the `tdd` cycle (one behavior at a time: a failing test seen red, then the code), every `Yours` decision it touches, quoted word for word, and that rule on `docs/`.
7. **Prove.** First commit what is left as `wip:`, so the tree is clean and the proof names this HEAD. Then run `verify` over every Done-when item. A failure → fix, then step 7 again from the commit, unticking every item. Tick an item once proven.
8. **Review** the proven HEAD; commit nothing. First `git status --porcelain` must print nothing; anything left (a fix made during proof) → commit it as `wip:` and go back to step 7, so the review diff, the proof and the patch-id name the same code. Delete the brief's old `## Final review`. `git diff origin/<trunk>...HEAD > "$v/final.diff"`; in a fork install also `.superflow/bin/ownership.sh --changed > "$v/ownership.txt"`. One `final-review` in Feature mode gets the brief, `$v/` (`final.diff`, `report.md`, `ownership.txt` in a fork), the HEAD sha and `rule://code-conventions`. Write its answer as `## Final review` under `Reviewed: <git rev-parse HEAD>`; a verdict counts only for the HEAD it names. `.superflow/bin/proof.sh verdict features/<slug>/PRD.md --head`: 0 → `.superflow/bin/proof.sh patch-id > "$v/patch-id"`, step 9; 3 (malformed) → rerun `final-review` once, a second 3 → stop and ask, never approval; 4 (no review block for this HEAD, or uncommitted code) → the review does not count: never edit `Reviewed:` to make it pass; step 7 again, then a fresh review; 1 → fix, step 7, review once more; a Critical or Important finding in that re-review → stop and ask before fixing, showing its findings. A fix that changes the brief (a Done-when item, any decision) → stop and ask, as step 4 says.
9. **Reply**: what you built, flow's defaults and why, the proof paths, the verdict. Next: `/ship`.

**Stop and ask** only for: a decision `AGENTS.md` reserves for the operator; in a fork install, an upstream-owned file needing more than a small inline edit (**Customizations**); a check still failing after two fix rounds, or a Critical or Important finding in a re-review (step 8); a change to the brief after the go (step 4); a case a `Yours` decision's words do not settle; something you cannot reach (credentials, outside services, hardware).

## The brief

```markdown
# <Feature>
<two lines: the problem, and why now>
## Data shape
<the types or tables, and the interface callers use>
## Decisions
- <topic>: "<the option the operator picked, word for word>". Yours.
- <topic>: <decision>. flow's default. Because <reason>. Rejected: <option> (<why not>).
## Done when
- [ ] <result a user sees, the app stores, or a call returns>. Proof: browser | tests
## Out of scope
- <item>: <why it is left out>
## Final review
Reviewed: <commit sha>
Verdict: approve | request changes
- Critical|Important|Minor: <finding> (path:line)
```

A decision the operator made is `Yours`: the option they picked, quoted word for word, never asked again; never reword, narrow or extend it, and never write flow's own reading into its line. A case its words do not settle (found while mapping, building or fixing) is a new question for the operator, not a flow default. A question left to `prototype` is `- <topic>: open — <question>` until its answer replaces it. `Proof: browser` for anything a user sees; `Proof: tests` for logic a test proves without the UI.
