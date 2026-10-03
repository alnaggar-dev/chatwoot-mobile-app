# Revert and reapply

`upstream-port revert <N|sha>`, only on the operator's word. A port revert is a git change, not a production rollback: applied migrations and any data-loss call are the operator's to decide. The hard guardrails and the `FORK_FLOW_PORT=1` rule of `SKILL.md` apply: every command that commits upstream's code (a revert and its `--continue`) carries it; fix commits of fork code run without it. `<trunk>` and `<upstream>` are the **Trunk** and **Upstream** values in `.omp/rules/commands.md`.

1. Clean tree, `git fetch --prune origin`. `<merge>` = that port's `port: upstream <tag>` commit; it must be in `origin/<trunk>`. From PR `<N>`: `port-land.sh` pushed its head SHA, so no merge commit names it; `h=$(gh pr view <N> --json headRefOid --jq .headRefOid)`, then `<merge>` = `git log -1 --first-parent --merges --format=%H --grep='^port: upstream ' "$h"`.
2. `git switch --no-track -c port/revert-<tag> origin/<trunk>`, `FORK_FLOW_PORT=1 git revert -m 1 --no-edit <merge>` (conflict → resolve, `FORK_FLOW_PORT=1 git revert --continue --no-edit`). Then the port's adapt commits, newest first, the same way (`git revert --no-edit <sha>`, `FORK_FLOW_PORT=1` on a `--continue`): `git log --format=%H --grep='^custom(port): adapt .* to upstream <tag>$' <merge>..origin/<trunk>`; they adapt fork code to the release's code, now gone. `.fork/check.sh`; a Verify failing because the release's code is gone → fix the entry or fork code in a follow-up commit.
3. Journal entry with `port-reverted: <revert sha>`, the tag and why.
4. Land as step 10 does: PR `chore: revert port upstream <tag>`, full CI, SHA-bound push (`.fork/port-land.sh <N>`; never force, never `gh pr merge`), cleanup, "Production: run `/ship <N>`". Never through `ship`: it would fold the untrailered revert into a customization.

Resume on `port/revert-*`, first missing piece: `REVERT_HEAD` → resolve, `FORK_FLOW_PORT=1 git revert --continue --no-edit`; no `port-reverted` line → write it; not pushed or no PR → step 10; head in `origin/<trunk>` with a merged PR → step 10's cleanup (`.fork/port-land.sh <N>` again). Abandon only on the operator's word: `git revert --abort`, `git switch <trunk>`, delete the branch locally and on origin.

## Reapply

The next `upstream-port` finds the unmatched `port-reverted` line (step 1) and reverts the revert first, committed before the release merge (step 3). With no newer release `port-map.sh` exits 3 and the port is the reapply alone, only on the operator's yes (`FORK_FLOW_PORT=1 git revert --no-commit <revert sha>`, step 3), its conflicts handled by steps 4–6, committed by step 7 as `port: reapply upstream <tag>` with the reverted merge's SHA in the body. Its range is the reverted port's: `<merge>` = the commit `<revert sha>` reverts, `pointer=$(git merge-base <merge>^1 <upstream>)`, `target=<merge>^2`. Steps 8–11 as usual, the PR titled `chore: reapply port upstream <tag>`.

Resuming a reapply alone: `REVERT_HEAD` exists and no release to merge → `<revert sha>` = `REVERT_HEAD`; resolve, step 4; step 7 commits. Staged changes with no port commit → `<revert sha>` from step 1's pending line, step 4.
