#!/usr/bin/env bash
# prove-verify.sh — runs one ledger entry's Verify in a throwaway worktree, to prove it fails without the change.
#
#   .fork/prove-verify.sh base <slug> [<file>...]   worktree at `git merge-base HEAD <upstream>`
#   .fork/prove-verify.sh head <slug> [<file>...]   worktree at HEAD (the pre-change commit)
#
# <upstream> is the **Upstream** value in .omp/rules/commands.md. Copies the working tree's .fork/check.sh,
# .fork/CHANGES.md and each named file (paths kept) into the worktree, runs `.fork/check.sh <slug>` there and
# prints its output. Name every program the Verify runs that the worktree lacks or has in an older version, and
# the data it reads; never the customization itself. Judging the failure message (this entry's own assertion,
# not a missing program) is the caller's.
# Exits with check.sh's exit; 2 with "could not run" on bad usage or a setup failure. The worktree is always removed.
# Called by the fork-change skill (step 5). Safe for bash 3.2 (the Mac's /bin/bash).
set -uo pipefail
cant() { printf 'prove-verify.sh: could not run: %s\n' "$*" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)" || cant "not in a git repository"

[ "$#" -ge 2 ] || cant "usage: .fork/prove-verify.sh base|head <slug> [<file>...]"
mode=$1 slug=$2; shift 2
case "$mode" in
  base)
    upstream=$(.superflow/bin/fact Upstream) || cant "no Upstream value in .omp/rules/commands.md"
    rev=$(git merge-base HEAD "$upstream") || cant "no merge-base with $upstream" ;;
  head) rev=$(git rev-parse --verify HEAD) || cant "no HEAD" ;;
  *) cant "first argument must be base or head, got '$mode'" ;;
esac
for f in .fork/check.sh .fork/CHANGES.md "$@"; do
  [ -f "$f" ] || cant "$f is not a file in the working tree"
done

d=$(mktemp -d) || cant "mktemp failed"
cleanup() { git worktree remove --force "$d" >/dev/null 2>&1; rm -rf "$d"; git worktree prune; }
trap cleanup EXIT
git worktree add -q --detach "$d" "$rev" >/dev/null 2>&1 || cant "git worktree add at $rev failed"
tar cf - .fork/check.sh .fork/CHANGES.md "$@" | tar xf - -C "$d" || cant "copying files into the worktree failed"

echo "== $mode $(git rev-parse --short "$rev"): .fork/check.sh $slug"
"$d/.fork/check.sh" "$slug" 2>&1
exit $?
