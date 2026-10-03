#!/usr/bin/env bash
# .superflow/bin/feature-branch.sh — cut or reuse feature/<slug>, deciding by containment, never by name.
#
# usage: .superflow/bin/feature-branch.sh <slug>
#        .superflow/bin/feature-branch.sh --check <slug>
#   <slug>  kebab-case: lowercase letters and digits joined by single hyphens.
#
# Stray check (--check runs only this: no fetch, no switch; normal mode runs it first, before any
# 'stay'): every tracked or untracked path under features/ (git ls-files -co, ignored files
# included) must be features/.gitkeep, a .DS_Store or ._* file, or under features/<slug>/; each
# other path is printed to stderr and the script exits 1. Clean: --check exits 0 silently.
#
# <trunk> is `.superflow/bin/fact Trunk`. After `git fetch origin <trunk>`, the first match wins:
#   - on port/*: fail (upstream-port owns port branches).
#   - on feature/<slug> with commits not in origin/<trunk>, or exactly at it: stay; its partial
#     work (committed or not) is fine.
#   - otherwise a branch moves, so `git status --porcelain` may list only CONTEXT.md, docs/adr/**
#     and features/<slug>/; anything else fails: ship that work first, it is never stashed or
#     switched over.
#   - feature/<slug> exists with commits not in origin/<trunk>: git switch feature/<slug>.
#   - HEAD is in origin/<trunk> (landed or empty): delete a landed or empty feature/<slug>
#     (git branch -D: -d checks HEAD, which may be a stale local <trunk>; containment is proven) —
#     detached at origin/<trunk> first only when it is checked out — then
#     git switch --no-track -c feature/<slug> origin/<trunk>. Never from local <trunk>:
#     merging a PR on the host does not update it.
#   - anything else is another feature's unlanded work: fail.
# Failure: a one-line reason on stderr, exit 1 (bad usage: exit 2). Success prints the branch.
# Safe under macOS /bin/bash 3.2.
set -euo pipefail

fail() {
	printf 'feature-branch: %s\n' "$1" >&2
	exit 1
}
slug_re='^[a-z0-9]+(-[a-z0-9]+)*$'
check_only=0
if [ "${1:-}" = --check ]; then
	check_only=1
	shift
fi
if [ $# -ne 1 ] || ! [[ $1 =~ $slug_re ]]; then
	printf 'usage: .superflow/bin/feature-branch.sh [--check] <kebab-case-slug>\n' >&2
	exit 2
fi
slug="$1"
branch="feature/$slug"

cd "$(git rev-parse --show-toplevel)"
stray=0
while IFS= read -r -d '' p; do
	case "$p" in
	features/.gitkeep | "features/$slug/"*) continue ;;
	esac
	case "${p##*/}" in
	.DS_Store | ._*) continue ;;
	esac
	printf 'feature-branch: stray %s (only features/%s/ belongs to this feature)\n' "$p" "$slug" >&2
	stray=1
done < <(git ls-files -co -z -- features/)
[ "$stray" = 0 ] || exit 1
[ "$check_only" = 0 ] || exit 0
trunk="$(.superflow/bin/fact Trunk)" || fail "no Trunk in .omp/rules/commands.md"
git fetch -q origin "$trunk" || fail "git fetch origin $trunk failed"
main="origin/$trunk"
current="$(git symbolic-ref -q --short HEAD || true)"

case "$current" in
port/*) fail "on $current: upstream-port owns port branches; finish or leave the port first" ;;
esac
if [ "$current" = "$branch" ] && { ! git merge-base --is-ancestor HEAD "$main" ||
	[ "$(git rev-parse HEAD)" = "$(git rev-parse "$main")" ]; }; then
	printf '%s\n' "$branch"
	exit 0
fi

allowed() {
	case "$1" in
	CONTEXT.md | docs/adr/* | "features/$slug/"*) return 0 ;;
	*) return 1 ;;
	esac
}
# -z: one NUL-terminated entry per path; a rename or copy carries its source as the next entry.
# -uall: untracked files one by one, never collapsed into a parent directory such as docs/.
while IFS= read -r -d '' entry; do
	allowed "${entry:3}" || fail "uncommitted ${entry:3} (only CONTEXT.md, docs/adr/ and features/$slug/ may move): ship it first"
	case "${entry:0:2}" in
	*R* | *C*)
		IFS= read -r -d '' source
		allowed "$source" || fail "uncommitted $source (only CONTEXT.md, docs/adr/ and features/$slug/ may move): ship it first"
		;;
	esac
done < <(git status --porcelain -z --untracked-files=all)

git merge-base --is-ancestor HEAD "$main" ||
	fail "${current:-detached HEAD} has commits not in $main (another feature's unlanded work): ship it first"
exists=0
git show-ref -q --verify "refs/heads/$branch" && exists=1
if [ "$exists" = 1 ] && ! git merge-base --is-ancestor "$branch" "$main"; then
	git switch -q "$branch" || fail "git switch $branch failed"
else
	if [ "$exists" = 1 ]; then
		if [ "$current" = "$branch" ]; then
			git switch -q --detach "$main" || fail "git switch --detach $main failed"
		fi
		git branch -q -D "$branch" || fail "git branch -D $branch failed"
	fi
	git switch -q --no-track -c "$branch" "$main" || fail "git switch -c $branch $main failed"
fi
printf '%s\n' "$branch"
