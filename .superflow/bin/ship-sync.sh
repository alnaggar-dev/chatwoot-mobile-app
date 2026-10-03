#!/usr/bin/env bash
# .superflow/bin/ship-sync.sh — ship step 4's catch-up with origin/<trunk> and the push.
#
# usage: .superflow/bin/ship-sync.sh <branch>              catch up, then push
#        .superflow/bin/ship-sync.sh --continue <branch>   after resolving a conflict
#
# <trunk> is `.superflow/bin/fact Trunk`.
#
# r = origin/<branch> (or none) is captured before `git fetch origin`. origin/<branch> moved off
# r, or r not an ancestor of HEAD → stop. A branch holding a merge commit takes
# `git merge origin/<trunk>`; else `git rebase origin/<trunk>` (never --autostash). Both
# run with the ours driver set as below, and so does every `rebase --continue`, so AGENTS.md
# text-merges even if some config sets that driver. A conflict (a rebase or merge left in
# progress) saves branch, r and mode in $(git rev-parse --git-dir)/superflow/ship-sync;
# --continue resumes from it. A rebase or merge that fails without starting exits 1 with git's
# message, nothing
# saved. --continue with nothing left in progress and the catch-up not done (such as after
# `git rebase --abort`) removes the saved state: run this script again.
# Then prints `git diff --stat origin/<trunk> -- AGENTS.md` for the prose check and pushes:
# never pushed → push -u; rewritten (r not an ancestor of HEAD) → --force-with-lease=<branch>:r;
# else a plain push. A refused push exits 3 only when `git ls-remote` shows origin/<branch> off
# r; otherwise 1 with git's message (a hook, the network). Prints the pushed head sha.
#
# Exit: 0 pushed, 1 error, 2 usage, 3 someone else pushed, 4 conflict to resolve.
# Safe under macOS /bin/bash 3.2.
set -euo pipefail

DRIVER='merge.ours.driver=git merge-file -L %X -L %S -L %Y %A %O %B'
die() { printf 'ship-sync: %s\n' "$*" >&2; exit 1; }
usage() { printf 'usage: .superflow/bin/ship-sync.sh [--continue] <branch>\n' >&2; exit 2; }

cont=0
[ "${1:-}" = --continue ] && { cont=1; shift; }
[ $# -eq 1 ] && [ -n "$1" ] && [ "${1#-}" = "$1" ] || usage
branch=$1

cd "$(git rev-parse --show-toplevel)" || die "not inside a git repository"
trunk=$(.superflow/bin/fact Trunk) || die "no Trunk in .omp/rules/commands.md"
BASE=origin/$trunk
GD=$(git rev-parse --absolute-git-dir)
mkdir -p "$GD/superflow"
STATE=$GD/superflow/ship-sync

in_progress() { [ -d "$GD/rebase-merge" ] || [ -d "$GD/rebase-apply" ] || [ -f "$GD/MERGE_HEAD" ]; }
conflict() {
	in_progress || {
		rm -f "$STATE"
		die "git $1 failed before any conflict (git's message above); nothing to continue: fix it, then run .superflow/bin/ship-sync.sh $branch again"
	}
	printf 'branch=%s\nr=%s\nmode=%s\n' "$branch" "$r" "$1" >"$STATE"
	git status --short >&2 || true
	printf 'ship-sync: conflict: resolve, then .superflow/bin/ship-sync.sh --continue %s\n' "$branch" >&2
	exit 4
}
other() {
	printf 'ship-sync: someone else pushed: bring it in first; stop and ask (%s)\n' "$*" >&2
	exit 3
}
field() { sed -n "s/^$1=//p" "$STATE"; }
push() { # <git push options>: a refusal is "someone else pushed" only when origin/<branch> left r
	git push "$@" origin "$branch" && return 0
	local cur
	cur=$(git ls-remote --heads origin "refs/heads/$branch") || die "git push origin $branch failed, and so did git ls-remote origin"
	cur=${cur%%[[:space:]]*}
	[ "${cur:-none}" = "$r" ] || other "origin/$branch moved: $r → ${cur:-none}"
	die "git push origin $branch failed with origin/$branch still at $r (git's message above)"
}

if [ $cont -eq 0 ]; then
	[ ! -e "$STATE" ] || die "$STATE exists: a sync is in progress, run --continue $branch"
	[ "$(git symbolic-ref -q --short HEAD)" = "$branch" ] || die "not on $branch"
	[ -z "$(git status --porcelain --untracked-files=no)" ] || die "uncommitted changes: commit first (never stash)"
	r=$(git rev-parse -q --verify "refs/remotes/origin/$branch^{commit}" || echo none)
	git fetch origin || die "git fetch origin failed"
	now=$(git rev-parse -q --verify "refs/remotes/origin/$branch^{commit}" || echo none)
	[ "$now" = "$r" ] || other "origin/$branch moved: $r → $now"
	if [ "$r" != none ] && ! git merge-base --is-ancestor "$r" HEAD; then
		other "origin/$branch ($r) is not in HEAD"
	fi
	if [ -n "$(git rev-list --merges "$BASE..HEAD")" ]; then
		git -c "$DRIVER" merge --no-edit "$BASE" || conflict merge
	else
		git -c "$DRIVER" rebase "$BASE" || conflict rebase
	fi
else
	[ -f "$STATE" ] || die "no saved sync in $STATE"
	[ "$(field branch)" = "$branch" ] || die "saved sync is for $(field branch), not $branch"
	r=$(field r) mode=$(field mode)
	case $mode in
	rebase)
		while [ -d "$GD/rebase-merge" ] || [ -d "$GD/rebase-apply" ]; do
			GIT_EDITOR=true git -c "$DRIVER" rebase --continue || conflict rebase
		done
		;;
	merge)
		if [ -f "$GD/MERGE_HEAD" ]; then git commit --no-edit || conflict merge; fi
		;;
	*) die "bad mode in $STATE" ;;
	esac
	# Nothing is in progress here: a rebase or merge still going exited 4 above.
	if ! git merge-base --is-ancestor "$BASE" HEAD; then
		rm -f "$STATE"
		die "nothing to continue and $BASE is not in HEAD (the $mode was abandoned): run .superflow/bin/ship-sync.sh $branch again"
	fi
	if [ "$(git symbolic-ref -q --short HEAD)" != "$branch" ]; then
		rm -f "$STATE"
		die "not on $branch after the $mode"
	fi
	rm -f "$STATE"
fi

git merge-base --is-ancestor "$BASE" HEAD || die "$BASE is not in HEAD: the catch-up did not complete"
git diff --stat "$BASE" -- AGENTS.md

if [ "$r" = none ]; then
	push -u
elif git merge-base --is-ancestor "$r" HEAD; then
	push
else
	push --force-with-lease="$branch:$r"
fi
git rev-parse HEAD
