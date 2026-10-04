Which skill for which need. Standing rules: `AGENTS.md`.

| Need | Skill |
|---|---|
| Build a feature | `/flow <request>`: brief, branch, build, prove, review; `/flow <slug>` resumes. Then `ship` |
| Vague idea → decisions | `grill` (optional; feeds `flow`) |
| Drive it in the browser | `verify` proves Done-when items in the browser or by tests (used by `flow`) |
| Docs, then the folder goes | `document` (run by `ship`) |
| Land it | `ship` |
| Small direct change (copy, a message, a setting) | edit it, then tell the operator "Run `/ship`." (`ship` reviews code no skill reviewed) |
| Any bug or perf regression | `diagnose`, then `ship` |
| Architecture pass (fork-owned code in a fork install) | `refactor`, then `ship` |
| Design spike | `prototype` |
| Edit the workflow kit itself (`.superflow/`) | change it in the SuperFlow kit and re-run its `install.sh` (files there are overwritten on update); project skills go in `.omp/skills/<name>/` |

Skills without a trigger of their own (`verify`, `tdd`, `refactor`, `prototype`) start only from this table or their caller: read `skill://<name>`.
