#!/usr/bin/env bash
# port-map.sh — upstream-port step 1's map: what the next port merges.
#
#   .fork/port-map.sh [target=<tag|<upstream>|sha>] [base=<rev>]
#
# <trunk>, <upstream> and <Release tags> are the **Trunk**, **Upstream** and **Release tags** values in
# .omp/rules/commands.md. Fetches (`git fetch --prune origin && git fetch --tags upstream`), then prints:
#   pointer=<last upstream commit merged into base>
#   target=<sha of the oldest release not merged>|none
#   tag=<that tag>|none
#   the backlog (`git log --oneline --first-parent pointer..target`)
#   pending-reapply=<revert sha>|none   (a `port-reverted:` line in .fork/PORTS.md with no later `port-reapplied:`)
# The target is always the oldest release. A named later target is printed as
# `requested: <x> (needs the operator's yes)` plus `requested-target=<sha>`, with its ancestry checked, never
# picked. A named target that is the oldest release prints `requested: <x> is the oldest release (no yes
# needed)` and no requested-target; one that is pointer itself (already merged) is refused.
# base defaults to origin/<trunk>. Both ancestry checks must pass for target and requested:
# `<x>` in <upstream> (a development-branch commit ships unreleased code) and pointer in `<x>`.
# Exit: 0 work to do, 3 nothing to port, 1 error or ancestry failure. Exit 3 with pending-reapply≠none: no release
# to merge, only the reapply, which needs the operator's yes (a reapply with a newer release exits 0).
# Called by the upstream-port skill (step 1) and .fork/port-dry-run.sh. Safe for bash 3.2.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

die() { echo "port-map: $*" >&2; exit 1; }
trunk=$(.superflow/bin/fact Trunk) || die "no Trunk value in .omp/rules/commands.md"
upstream=$(.superflow/bin/fact Upstream) || die "no Upstream value in .omp/rules/commands.md"
tags=$(.superflow/bin/fact 'Release tags') || die "no Release tags value in .omp/rules/commands.md"
req="" base=origin/$trunk
for a in "$@"; do
  case $a in
    target=*) req=${a#target=} ;;
    base=*) base=${a#base=} ;;
    *) die "usage: .fork/port-map.sh [target=<tag|$upstream|sha>] [base=<rev>]" ;;
  esac
done

git fetch --prune origin >&2 && git fetch --tags upstream >&2 || die "fetch failed"
pointer=$(git merge-base "$base" "$upstream") || die "no merge-base of $base and $upstream"
tag=$(git tag --list "$tags" --merged "$upstream" --no-merged "$base" --sort=v:refname | sed -n 1p)
target=none
if [ -n "$tag" ]; then
  target=$(git rev-parse "$tag^{commit}") || die "cannot resolve $tag"
else
  tag=none
fi

check() { # <sha> <label>
  git merge-base --is-ancestor "$1" "$upstream" || die "$2 is not in $upstream (unreleased code)"
  git merge-base --is-ancestor "$pointer" "$1" || die "$2 does not contain pointer $pointer"
}

echo "pointer=$pointer"
echo "target=$target"
echo "tag=$tag"
backlog=""
if [ "$target" != none ]; then
  check "$target" "$tag"
  backlog=$(git log --oneline --first-parent "$pointer..$target")
  if [ -n "$backlog" ]; then printf '%s\n' "$backlog"; fi
fi

pending=$({ grep -E '^port-(reverted|reapplied): ' .fork/PORTS.md 2>/dev/null || true; } |
  awk '{ s = $2 } /^port-reverted:/ { open[s] = NR; order[NR] = s } /^port-reapplied:/ { delete open[s] }
       END { last = ""; for (i = 1; i <= NR; i++) if ((i in order) && (order[i] in open) && open[order[i]] == i) last = order[i]; print last }')
echo "pending-reapply=${pending:-none}"

if [ -n "$req" ]; then
  r=$(git rev-parse --verify --quiet "$req^{commit}") || die "cannot resolve requested target $req"
  [ "$r" != "$pointer" ] || die "requested $req is pointer $pointer: already merged, nothing to merge"
  if [ "$r" = "$target" ]; then
    echo "requested: $req is the oldest release (no yes needed)"
  else
    echo "requested: $req (needs the operator's yes)"
    check "$r" "requested $req"
    printf '%s\n' "requested-target=$r"
    backlog=requested
  fi
fi

if [ -z "$backlog" ]; then
  [ -z "$pending" ] && { echo "port-map: nothing to port" >&2; exit 3; }
  echo "port-map: no release to merge; the reapply alone of $pending needs the operator's yes (REVERT.md)" >&2
  exit 3
fi
exit 0
