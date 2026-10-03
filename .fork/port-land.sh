#!/usr/bin/env bash
# port-land.sh — upstream-port step 10's land: SHA-bound push of a green port PR to <trunk>.
#
#   .fork/port-land.sh <N>
#
# <trunk> is the **Trunk** value in .omp/rules/commands.md. Requires: `gh repo set-default --view` is origin's
# repository; PR <N> open from a port/* branch; on the PR's statusCheckRollup, every check name's latest run (by
# startedAt) concluded SUCCESS, NEUTRAL or SKIPPED (a failed or running rerun after an old success counts as not
# passed), `registry-gate` among them; unless **Full suite in CI** is `none`, each check-name pattern in its second
# value (comma-separated, `*` matches any text) matches at least one check and every match is SUCCESS (skipped or
# missing full-suite jobs never land); local HEAD equals the PR's headRefOid. Head, state, branch and checks come
# from one gh snapshot, so the checks belong to the head that is pushed.
# Then `git fetch origin`; origin/<trunk> must be an ancestor of the head, else exit 3 (catch-up merge, step 10
# item 2). Pushes `<sha>:refs/heads/<trunk>` (never force), waits until the PR shows MERGED (a port branch deleted
# first can leave it CLOSED), then `git fetch origin`, `git switch <trunk> && git merge --ff-only origin/<trunk>`
# (refused → stop, never reset),
# deletes the port branch only when its local and remote tips are in origin/<trunk> (`-d` locally; on origin a
# delete leased to the fetched tip; else stop, branch kept), and prints "Production: run `/ship <N>`" without
# running it.
# Rerun after a partial land: if PR <N> is MERGED and its headRefOid is an ancestor of (or equal to)
# origin/<trunk> after `git fetch origin`, checks and push are skipped and only the cleanup runs (switch +
# fast-forward, the same checked deletes of the local and origin port branch, print). Pushed but not yet MERGED
# after the wait → exit 1; rerun later. Any other non-OPEN state is refused.
# Exit: 0 landed (or cleanup finished), 1 refused or failed (reason on stderr), 2 usage, 3 <trunk> moved.
# Called by the upstream-port skill (step 10, and REVERT.md's land). Safe for bash 3.2 (the Mac's /bin/bash).
set -euo pipefail

die() { echo "port-land: $*" >&2; exit 1; }
case "${1:-}" in ''|*[!0-9]*) echo "usage: .fork/port-land.sh <N>" >&2; exit 2 ;; esac
[ $# -eq 1 ] || { echo "usage: .fork/port-land.sh <N>" >&2; exit 2; }
n=$1
cd "$(git rev-parse --show-toplevel)" || exit 1
trunk=$(.superflow/bin/fact Trunk) || die "no Trunk value in .omp/rules/commands.md"

want=$(git remote get-url origin | sed 's#\.git$##; s#/$##' | tr ':' '/' | awk -F/ '{ print $(NF-1) "/" $NF }') ||
  die "no origin remote"
repo=$(gh repo set-default --view 2>/dev/null) || die "gh repo set-default --view failed: run gh repo set-default $want"
[ "$repo" = "$want" ] || die "gh default repo is '$repo', not origin's $want: run gh repo set-default $want"

# One snapshot: head, state, branch, then `<conclusion>\t<name>` of each check name's latest run.
snap=$(gh pr view "$n" --json headRefOid,statusCheckRollup,state,headRefName --jq '.headRefOid, .state, .headRefName,
  ([.statusCheckRollup[] | {n: (.name // .context), t: (.startedAt // .createdAt // ""),
  c: (.conclusion // .state // "")}] | group_by(.n)[] | max_by(.t) | "\(.c)\t\(.n)")') \
  || die "gh pr view $n failed"
sha=$(printf '%s\n' "$snap" | sed -n 1p)
state=$(printf '%s\n' "$snap" | sed -n 2p)
br=$(printf '%s\n' "$snap" | sed -n 3p)
runs=$(printf '%s\n' "$snap" | sed '1,3d')
case "$br" in port/*) ;; *) die "PR $n head branch '$br' is not port/*" ;; esac

cleanup() {
  git fetch origin || die "git fetch origin failed"
  git switch "$trunk" || die "git switch $trunk failed"
  git merge --ff-only "origin/$trunk" || die "git merge --ff-only origin/$trunk refused: stop, never reset"
  local rc=0 rem=''
  if git show-ref --verify --quiet "refs/heads/$br"; then
    git merge-base --is-ancestor "refs/heads/$br" "origin/$trunk" || die "local $br has commits not on origin/$trunk; branch kept"
    git branch -d "$br" || die "git branch -d $br refused"
  fi
  git ls-remote --exit-code --heads origin "refs/heads/$br" >/dev/null || rc=$?
  case $rc in 0 | 2) ;; *) die "git ls-remote origin $br failed" ;; esac
  if [ $rc = 0 ]; then
    git fetch --quiet --no-tags origin "refs/heads/$br" || die "git fetch origin $br failed"
    rem=$(git rev-parse --verify FETCH_HEAD) || die "git rev-parse FETCH_HEAD failed"
    git merge-base --is-ancestor "$rem" "origin/$trunk" \
      || die "origin's $br ($rem) has commits not on origin/$trunk; branch kept: stop and ask"
    git push --force-with-lease="refs/heads/$br:$rem" origin --delete "$br" \
      || die "deleting origin/$br failed (it moved off $rem?)"
  fi
  echo "Production: run \`/ship $n\`"
  exit 0
}

if [ "$state" = MERGED ]; then
  git fetch origin || die "git fetch origin failed"
  git merge-base --is-ancestor "$sha" "origin/$trunk" 2>/dev/null \
    || die "PR $n is MERGED but head $sha is not on origin/$trunk"
  cleanup
fi
[ "$state" = OPEN ] || die "PR $n is $state, not OPEN"

bad=$(printf '%s\n' "$runs" | awk -F'\t' 'NF && $1 != "SUCCESS" && $1 != "NEUTRAL" && $1 != "SKIPPED" { printf "\n  %s (%s)", $2, ($1 == "" ? "running" : $1) }')
[ -z "$bad" ] || die "checks not passed on $sha:$bad"
printf '%s\n' "$runs" | cut -f2 | grep -qxF registry-gate || die "no registry-gate check on $sha yet: wait for it"
# The full suite must have run: each **Full suite in CI** check-name pattern (its second value) matches a SUCCESS.
ci=$(.superflow/bin/fact "Full suite in CI") || die "no Full suite in CI value in .omp/rules/commands.md"
if [ "$ci" != none ]; then
  names=$(.superflow/bin/fact "Full suite in CI" 2) || die "Full suite in CI names no full-suite checks (its second value)"
  [ "$names" != none ] || die "Full suite in CI names no full-suite checks (its second value)"
  set -f
  IFS=, read -r -a pats <<EOF
$names
EOF
  set +f
  seen=0
  for pat in "${pats[@]}"; do
    pat="${pat#"${pat%%[![:space:]]*}"}" pat="${pat%"${pat##*[![:space:]]}"}"
    [ -n "$pat" ] || continue
    seen=1 hit=0
    while IFS=$'\t' read -r c name; do
      # shellcheck disable=SC2254 # the pattern is a glob
      case "$name" in $pat) [ "$c" = SUCCESS ] || die "full-suite check '$name' is ${c:-running} on $sha"; hit=1 ;; esac
    done <<EOF
$runs
EOF
    [ "$hit" = 1 ] || die "no check matching '$pat' on $sha: the full suite has not run"
  done
  [ "$seen" = 1 ] || die "Full suite in CI names no full-suite checks (its second value)"
fi

[ "$(git rev-parse HEAD)" = "$sha" ] || die "local HEAD $(git rev-parse HEAD) is not PR head $sha"

git fetch origin || die "git fetch origin failed"
if ! git merge-base --is-ancestor "origin/$trunk" "$sha"; then
  echo "$trunk moved: catch-up merge (step 10 item 2)" >&2
  exit 3
fi

git push origin "$sha:refs/heads/$trunk" || die "push to $trunk refused (never force)"
i=0
while [ "$(gh pr view "$n" --json state --jq .state 2>/dev/null || true)" != MERGED ]; do
  i=$((i + 1))
  [ "$i" -le 30 ] || die "pushed $sha to $trunk, but PR $n is not MERGED yet: rerun .fork/port-land.sh $n (cleanup only)"
  sleep 10
done
cleanup
