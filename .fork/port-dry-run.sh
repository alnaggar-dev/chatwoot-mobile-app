#!/usr/bin/env bash
# port-dry-run.sh — upstream-port's Dry run: what the next port would conflict on, changing nothing.
#
#   .fork/port-dry-run.sh [target=<tag|<upstream>|sha>] [base=<rev>]
#
# Runs step 1's map (.fork/port-map.sh, same arguments; a named target is used here, since nothing lands),
# `./.fork/setup.sh --check` and the **Port preflight** command (skipped when `none`) in the checkout ($d has no
# installed dependencies). No resume, clean-tree or gh checks. Keys are read from .omp/rules/commands.md.
# Throwaway worktree at base (default origin/<trunk>), then
#   git -c rerere.enabled=false -c merge.ours.driver=true merge --no-ff --no-commit <target>
# Rerere stays off: shared by every worktree, it would record throwaway resolutions and hide conflicts.
# Prints the conflicts, migration collisions (duplicate lines of the **Migration versions** command run in $d,
# skipped when `none`: collisions merge cleanly), the pending reapply and the disturbed entries
# (.fork/tripwires.sh hits, read from the checkout's ledger, not $d's). Cleanup always runs, even after a
# failure: merge --abort, worktree remove --force, worktree prune. The worktree is added with --quiet.
# Exit: 0 report printed or nothing to merge (port-map exit 3; a reapply alone is reported as needing the operator's
# yes), 1 error, 4 the preflight failed (its message above; stops before the merge: a missing mergiraf driver
# would change the conflict list).
# Called by the upstream-port skill (`dry-run` argument). Safe for bash 3.2.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

trunk=$(.superflow/bin/fact Trunk) || exit 1
preflight=$(.superflow/bin/fact 'Port preflight') || exit 1
versions=$(.superflow/bin/fact 'Migration versions') || exit 1
base=origin/$trunk
for a in "$@"; do
  case $a in
    base=*) base=${a#base=} ;;
    target=*) ;;
    *) echo "usage: .fork/port-dry-run.sh [target=<tag|<upstream>|sha>] [base=<rev>]" >&2; exit 1 ;;
  esac
done

rc=0; map=$(.fork/port-map.sh "$@") || rc=$?
printf '%s\n' "$map"
if [ "$rc" = 3 ]; then
  case $map in
    *pending-reapply=none*) echo "dry-run: nothing to merge." ;;
    *) echo "dry-run: no release to merge; the reapply alone (pending-reapply above) needs the operator's yes." ;;
  esac
  exit 0
fi
[ "$rc" = 0 ] || exit 1
field() { printf '%s\n' "$map" | sed -n "s/^$1=//p"; }
pointer=$(field pointer) target=$(field requested-target)
[ -n "$target" ] || target=$(field target)

./.fork/setup.sh --check || { echo "dry-run: ./.fork/setup.sh --check failed (above); run ./.fork/setup.sh, then rerun the dry run" >&2; exit 4; }
if [ "$preflight" != none ]; then
  bash -c "$preflight" </dev/null || { echo "dry-run: the Port preflight command failed (message above); fix it, then rerun the dry run" >&2; exit 4; }
fi

d=$(mktemp -d)
cleanup() {
  git -C "$d" merge --abort 2>/dev/null || true
  git worktree remove --force "$d" 2>/dev/null || true
  git worktree prune
  rm -rf "$d"
}
trap cleanup EXIT
git worktree add --quiet --detach "$d" "$base" >&2

git -C "$d" -c rerere.enabled=false -c merge.ours.driver=true merge --no-ff --no-commit "$target" >/dev/null 2>&1 || true
echo "conflicts:"
git -C "$d" -c core.quotePath=false diff --name-only --diff-filter=U | sed 's/^/  /'
if [ "$versions" != none ]; then
  echo "migration collisions:"
  (cd "$d" && bash -c "$versions" </dev/null) | sort | uniq -d | sed 's/^/  /'
fi
echo "disturbed entries:"
.fork/tripwires.sh hits "$pointer" "$target" || exit 1
