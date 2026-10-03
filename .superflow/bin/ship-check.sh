#!/usr/bin/env bash
# .superflow/bin/ship-check.sh — ship step 2's checks on the change since origin/<trunk>.
#
# usage: .superflow/bin/ship-check.sh            run every check, name each red one
#        .superflow/bin/ship-check.sh situate    print each features/<slug>/ folder and each file
#                                                directly under features/ (but .gitkeep)
#
# Checks, all run from the repo root against b=$(git merge-base HEAD origin/<trunk>), <trunk>
# being `.superflow/bin/fact Trunk`:
#   near tests   .superflow/bin/near-tests.sh "$b": 1 is red; any other non-zero exit means it
#                could not run
#   lint         git diff --name-only --no-renames --diff-filter=ACMR "$b", kept by the
#                **Lint changed files** globs (`fact "Lint changed files" 2`: comma-separated
#                shell patterns, `*` crosses `/`, a leading `!` excludes); runs value 1 with the
#                literal `<files…>` replaced by the shell-quoted list (appended when absent).
#                `none` or an empty list runs nothing.
#   debug marker `[DEBUG` + `-` in any tracked or untracked non-ignored file but *.md.
#   prototype    `PROTOTYPE` + `-THROWAWAY` in tracked or staged files outside
#                .superflow/skills/ and .omp/skills/ (untracked scratch is not shipped).
# Both markers are built at runtime so this file never matches itself.
# situate lists from `git ls-files -co` without --exclude-standard (ignored files count);
# .DS_Store and ._* are skipped.
#
# Exit: 0 all green (situate: listed), 1 a check red, 2 could not run (usage, git failure,
# no merge-base, an unreadable Lint key, a marker grep that failed, near-tests exiting neither
# 0 nor 1). Every check still runs after a near-tests that could not run; the last line names
# each red one and it. Safe under macOS /bin/bash 3.2.
set -euo pipefail

die() { printf 'ship-check: %s\n' "$*" >&2; exit 2; }
root=$(git rev-parse --show-toplevel) || die "not inside a git repository"
cd "$root"

if [ $# -eq 1 ] && [ "$1" = situate ]; then
	list=$(git ls-files -co -z -- features/ ':!features/.gitkeep' | tr '\0' '\n') || die "git ls-files failed"
	[ -n "$list" ] || exit 0
	printf '%s\n' "$list" | awk -F/ '$NF == ".DS_Store" || $NF ~ /^\._/ { next }
		NF > 2 { print $1 "/" $2 "/"; next } { print }' | sort -u
	exit 0
fi
[ $# -eq 0 ] || { printf 'usage: .superflow/bin/ship-check.sh [situate]\n' >&2; exit 2; }

trunk=$(.superflow/bin/fact Trunk) || die "no Trunk in .omp/rules/commands.md"
b=$(git merge-base HEAD "origin/$trunk") || die "git merge-base HEAD origin/$trunk failed"
lint=$(.superflow/bin/fact "Lint changed files") || die "could not read Lint changed files"
globs=""
if [ "$lint" != none ]; then
	globs=$(.superflow/bin/fact "Lint changed files" 2) || die "could not read the Lint changed files globs"
fi
red="" cant=""
mark() { red="$red $1"; printf 'ship-check: RED %s\n' "$1" >&2; }

rc=0; .superflow/bin/near-tests.sh "$b" || rc=$?
case $rc in
0) ;;
1) mark "near-tests" ;;
*) cant="near-tests"; printf 'ship-check: COULD NOT RUN near-tests (exit %s)\n' "$rc" >&2 ;;
esac

# lint_keeps <path>: the last matching pattern decides (a `!` pattern excludes); none matches → skip.
lint_keeps() {
	local keep=1 pat
	set -f
	local IFS=,
	for pat in $globs; do
		pat="${pat#"${pat%%[![:space:]]*}"}"
		pat="${pat%"${pat##*[![:space:]]}"}"
		[ -n "$pat" ] || continue
		case "$pat" in
		!*)
			# shellcheck disable=SC2254 # the pattern is a glob
			case "$1" in ${pat#!}) keep=1 ;; esac
			;;
		*)
			# shellcheck disable=SC2254
			case "$1" in $pat) keep=0 ;; esac
			;;
		esac
	done
	set +f
	return "$keep"
}

if [ "$lint" != none ]; then
	changed=$(mktemp) || die "mktemp failed"
	trap 'rm -f "$changed"' EXIT
	git diff -z --name-only --no-renames --diff-filter=ACMR "$b" >"$changed" || die "git diff failed"
	files=""
	while IFS= read -r -d '' f; do
		lint_keeps "$f" || continue
		files="$files $(printf '%q' "$f")"
	done <"$changed"
	if [ -n "$files" ]; then
		files="${files# }"
		ph='<files…>'
		case "$lint" in
		*"$ph"*) cmd="${lint%%"$ph"*}$files${lint#*"$ph"}" ;;
		*) cmd="$lint $files" ;;
		esac
		bash -c "$cmd" || mark "lint"
	fi
fi

dbg='[DEBUG'; dbg="$dbg-"
rc=0; git grep --untracked -nF "$dbg" -- ':!*.md' || rc=$?
case $rc in
0) mark "debug marker $dbg" ;;
1) ;;
*) die "git grep for $dbg could not run (exit $rc)" ;;
esac

proto='PROTOTYPE'; proto="$proto-THROWAWAY"
rc=0; git grep -nF "$proto" -- . ':!.superflow/skills/**' ':!.omp/skills/**' || rc=$?
case $rc in
0) mark "prototype marker $proto" ;;
1) ;;
*) die "git grep for $proto could not run (exit $rc)" ;;
esac

[ -z "$red" ] || printf 'ship-check: red:%s\n' "$red" >&2
if [ -n "$cant" ]; then
	printf 'ship-check: could not run: %s\n' "$cant" >&2
	exit 2
fi
[ -z "$red" ] || exit 1
printf 'ship-check: all green\n'
