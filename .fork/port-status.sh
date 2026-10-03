#!/usr/bin/env bash
# port-status.sh — upstream-port's Resume: finds an unfinished port and prints where to go on.
#
#   .fork/port-status.sh
#
# <trunk> and <upstream> are the **Trunk** and **Upstream** values in .omp/rules/commands.md.
# Runs `git fetch --prune origin`, then looks for refs/heads/port/* and refs/remotes/origin/port/*.
# Prints `branch:`, `state:`, `next:` and the rules a resumed port must keep, plus `pointer=`/`target=`/`tag=`
# when a port commit exists (in a catch-up merge too: they come from the port commit) or a release merge
# is in progress (`target` = MERGE_HEAD's commit). `tag=` is `git describe --tags --exact-match <target>`,
# empty when target has no tag. Routes by what git shows, first match wins (the skill's Resume list).
# Read-only apart from the fetch: never switches branches (prints the `git switch` to run). Before any
# `gh pr list` it checks `gh repo set-default --view` is origin's repository (with two remotes gh may pick
# upstream's repo and see no PR). A pushed branch whose HEAD is already on origin/<trunk> with no PR merged
# at HEAD is reported as such (stop and ask), never as a fresh port.
# Exit: 0 a port to resume, 3 none, 1 error (fetch, gh failure or wrong gh default repo; reason on stderr).
# Called by the upstream-port skill (step 1 runs it first). Safe for bash 3.2.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

die() { echo "port-status: $*" >&2; exit 1; }
trunk=$(.superflow/bin/fact Trunk) || die "no Trunk value in .omp/rules/commands.md"
upstream=$(.superflow/bin/fact Upstream) || die "no Upstream value in .omp/rules/commands.md"
git fetch --prune origin >&2 || die "fetch failed"
refs=$(git for-each-ref --format='%(refname:short)' refs/heads/port/ refs/remotes/origin/port/ | sed 's#^origin/##' | sort -u)
[ -z "$refs" ] && { echo "port-status: no unfinished port"; exit 3; }

cur=$(git symbolic-ref --quiet --short HEAD || true)
branch=$(printf '%s\n' "$refs" | sed -n 1p)
printf '%s\n' "$refs" | grep -qxF -- "$cur" && branch=$cur
n=$(printf '%s\n' "$refs" | wc -l | tr -d ' ')
[ "$n" -gt 1 ] && echo "ports open: $(printf '%s\n' "$refs" | tr '\n' ' ')(never cut a second port while one exists)"

echo "branch: $branch"
rules() {
  echo "rule: never a second \`port: upstream\` commit."
  echo "rule: in a catch-up merge, pointer/target come from the port commit, never MERGE_HEAD."
  echo "rule: a port/revert-* branch resumes in REVERT.md."
  echo "rule: red CI → fix commit WITHOUT FORK_FLOW_PORT, rerun the failing checks locally, push."
  echo "rule: cleanup skips what is gone."
}
out() { echo "state: $1"; echo "next: $2"; rules; exit 0; }
gh_repo() { # gh must answer for the fork's repo (origin's), or its PR list means nothing
  local r want
  want=$(git remote get-url origin | sed 's#\.git$##; s#/$##' | tr ':' '/' | awk -F/ '{ print $(NF-1) "/" $NF }')
  r=$(gh repo set-default --view 2>/dev/null) || die "gh repo set-default --view failed: run gh repo set-default $want, then rerun"
  [ "$r" = "$want" ] || die "gh default repo is '$r', not origin's $want: run gh repo set-default $want, then rerun"
}
# range PORT → prints pointer=/target=/tag= of the merge PORT records (a reapply's body names the reverted merge)
range() {
  local merge=$1
  if git log -1 --format=%s "$1" | grep -q '^port: reapply upstream '; then
    merge=$(git log -1 --format=%b "$1" | grep -oE '[0-9a-f]{7,40}' | while read -r s; do
      [ "$(git rev-list --parents -n1 "$s" 2>/dev/null | wc -w)" -ge 3 ] && { git rev-parse "$s"; break; }; done || true)
    [ -n "$merge" ] || out "reapply port commit $1 names no reverted merge" "stop and ask"
  fi
  echo "pointer=$(git merge-base "$merge^1" "$upstream")"
  target "$(git rev-parse "$merge^2")"
}
target() { echo "target=$1"; echo "tag=$(git describe --tags --exact-match "$1" 2>/dev/null || true)"; }

case $branch in
  port/revert-*)
    [ "$cur" = "$branch" ] || out "revert branch, not checked out" "git switch $branch, then REVERT.md (Revert and reapply)"
    out "revert branch" "REVERT.md (Revert and reapply)" ;;
esac
if [ "$cur" != "$branch" ]; then
  out "not checked out" "git switch $branch, then rerun .fork/port-status.sh"
fi

port=$(git log -1 -E --format=%H --grep='^port: (reapply )?upstream ' "origin/$trunk..HEAD")
gd=$(git rev-parse --git-dir)
if [ -f "$gd/REVERT_HEAD" ]; then
  out "revert in progress (REVERT_HEAD $(git rev-parse --short REVERT_HEAD))" \
    "step 3's reapply. A release to merge (step 1 lists one): resolve, FORK_FLOW_PORT=1 git revert --continue --no-edit, rest of step 3. None (reapply alone; <revert sha> = REVERT_HEAD): resolve, step 4; step 7 commits."
fi
if [ -f "$gd/MERGE_HEAD" ]; then
  if git merge-base --is-ancestor MERGE_HEAD "$upstream"; then
    echo "pointer=$(git merge-base HEAD "$upstream")"
    target "$(git rev-parse 'MERGE_HEAD^{commit}')"
    out "release merge in progress" "step 4 (pointer is still the old base mid-merge)"
  fi
  if git merge-base --is-ancestor MERGE_HEAD "origin/$trunk"; then
    [ -n "$port" ] || out "catch-up merge in progress, but no port commit on $branch" "stop and ask"
    range "$port"
    out "catch-up merge in progress" "step 10's catch-up with the pointer/target above (from the port commit, never MERGE_HEAD); resolve and commit as step 10 item 2 says, push, wait"
  fi
  out "merge of an unknown commit in progress" "stop and ask"
fi

if [ -z "$port" ]; then
  if git merge-base --is-ancestor HEAD "origin/$trunk" && git rev-parse -q --verify "origin/$branch" >/dev/null; then
    command -v gh >/dev/null ||
      out "pushed, HEAD already on origin/$trunk" "gh missing: check by hand whether the PR for $branch merged at HEAD (yes → step 10's cleanup; no → stop and ask)"
    gh_repo
    merged=$(gh pr list --head "$branch" --state merged --json headRefOid --jq '.[].headRefOid') || die "gh pr list failed"
    printf '%s\n' "$merged" | grep -qxF "$(git rev-parse HEAD)" && out "landed" "step 10's cleanup only; skip what is gone"
    out "pushed, HEAD already on origin/$trunk, but no PR for $branch merged at HEAD" "stop and ask"
  fi
  if ! git diff --cached --quiet; then
    out "staged reapply, stopped before step 7" "step 4 (<revert sha> from step 1's pending line)"
  fi
  out "no port commit, clean tree" "step 1's checks, then step 3"
fi

range "$port"
if git diff --quiet "$port" HEAD -- .fork/PORTS.md; then
  out "port commit, no journal" "step 8 (it only reads; fixes show in git log $port..HEAD)"
fi
if [ "$(git rev-parse --verify --quiet "origin/$branch" || true)" != "$(git rev-parse HEAD)" ]; then
  out "journal written, not pushed" "step 10's push"
fi
command -v gh >/dev/null || out "pushed" "gh missing: check the PR for $branch by hand (step 10)"
gh_repo
st=$(gh pr list --head "$branch" --state all --json state --jq '.[0].state // ""') || die "gh pr list failed"
case $st in
  "") out "pushed, no PR" "create the PR (step 10)" ;;
  OPEN) out "PR open" "step 10's wait and land; red CI → fix commit without FORK_FLOW_PORT, rerun the failing checks locally, push" ;;
  MERGED) out "PR merged" "step 10's cleanup; skip what is gone" ;;
  *) out "PR closed unmerged" "stop and ask" ;;
esac
