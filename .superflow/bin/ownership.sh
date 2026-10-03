#!/usr/bin/env bash
# .superflow/bin/ownership.sh — name the owner of each path: fork-owned or upstream-owned.
#
# usage: .superflow/bin/ownership.sh [--base <rev>] <path>...
#        .superflow/bin/ownership.sh --changed [--base <rev>]
#   <path>        repository-relative, resolved from the toplevel; absolute, empty or with a `..`
#                 component → exit 2. A path in neither the working tree, HEAD nor the base (a
#                 typo) → exit 2, nothing printed; a deleted path HEAD or the base still has is judged.
#   --base <rev>  the upstream base; default git merge-base HEAD <upstream>, <upstream> being
#                 `.superflow/bin/fact Upstream` (fails → exit 2). Without --base on a base
#                 install (no readable Upstream) → exit 2: ownership applies to fork installs.
#                 Inside a port pass upstream-port's pointer.
#   --changed     judge the feature's change set instead of explicit paths (combining them → exit 2):
#                 every path committed, uncommitted or deleted since git merge-base HEAD
#                 origin/<trunk> (<trunk> = `fact Trunk`; fails → exit 2), plus untracked
#                 non-ignored files; sorted, unique. Deleted paths are judged the same way.
#                 Empty set: prints nothing, exit 0.
#
# Prints `<path>\tfork-owned` or `<path>\tupstream-owned` per path, in order. Fork-owned (free to
# restructure) when `git check-attr merge -- <path>` prints `ours` or the base lacks the path
# (directories too). Upstream-owned paths take inline edits only (the fork rules): never moved,
# split or restructured. Safe under macOS /bin/bash 3.2.
set -euo pipefail

usage() {
	printf 'usage: .superflow/bin/ownership.sh [--base <rev>] <path>... | --changed [--base <rev>]\n' >&2
	exit 2
}
err() {
	printf 'ownership: %s\n' "$1" >&2
	exit 2
}
base=""
changed=0
while [ $# -gt 0 ]; do
	case "$1" in
	--base)
		[ $# -ge 2 ] && [ -n "$2" ] || usage
		base="$2"
		shift 2
		;;
	--changed)
		changed=1
		shift
		;;
	*) break ;;
	esac
done
if [ "$changed" = 1 ]; then
	[ $# -eq 0 ] || usage
else
	[ $# -ge 1 ] || usage
fi
for p in "$@"; do
	[ -n "$p" ] || err "empty path"
	case "$p" in /*) err "$p: absolute path; pass it repository-relative" ;; esac
	case "/$p/" in */../*) err "$p: a .. component is not repository-relative" ;; esac
done

cd "$(git rev-parse --show-toplevel)"
if [ -z "$base" ]; then
	upstream="$(.superflow/bin/fact Upstream 2>/dev/null)" || err "no upstream: ownership applies to fork installs (or pass --base)"
	base="$(git merge-base HEAD "$upstream")" || err "git merge-base HEAD $upstream failed; fetch upstream or pass --base"
fi
paths=()
if [ "$changed" = 1 ]; then
	trunk="$(.superflow/bin/fact Trunk)" || err "no Trunk in .omp/rules/commands.md"
	mb="$(git merge-base HEAD "origin/$trunk")" || err "git merge-base HEAD origin/$trunk failed; fetch origin $trunk"
	while IFS= read -r -d '' p; do
		paths+=("$p")
	done < <({ git diff -z --name-only --no-renames "$mb" && git ls-files -z -o --exclude-standard; } | LC_ALL=C sort -z -u)
	[ "${#paths[@]}" -gt 0 ] || exit 0
else
	paths=("$@")
fi
git rev-parse -q --verify "$base^{commit}" >/dev/null || err "$base is not a commit"
if [ "$changed" = 0 ]; then
	for p in "${paths[@]}"; do
		q="$p"
		[ "$p" = . ] && q=""
		[ -e "$p" ] || [ -L "$p" ] || git cat-file -e "HEAD:$q" 2>/dev/null || git cat-file -e "$base:$q" 2>/dev/null ||
			err "$p: not in the working tree, at HEAD or at $base (typo?)"
	done
fi

for p in "${paths[@]}"; do
	attr="$(git check-attr merge -- "$p")"
	q="$p"
	[ "$p" = . ] && q=""
	if [ "${attr##*: }" = ours ] || ! git cat-file -e "$base:$q" 2>/dev/null; then
		printf '%s\tfork-owned\n' "$p"
	else
		printf '%s\tupstream-owned\n' "$p"
	fi
done
