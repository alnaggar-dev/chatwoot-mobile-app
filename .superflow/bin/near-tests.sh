#!/usr/bin/env bash
# .superflow/bin/near-tests.sh — run the tests next to every path changed since <base>.
#
# usage: .superflow/bin/near-tests.sh [--list] [<base>]
#   <base>  default: git merge-base HEAD origin/<trunk> (must resolve; <trunk> is
#           `.superflow/bin/fact Trunk`). The change set is committed, uncommitted and
#           untracked (non-ignored) paths since it, deleted ones included, so a
#           `git reset --soft` fold to the merge-base changes nothing.
#   --list  print the chosen test files; run nothing.
#
# The map and the runner live in .superflow/project.sh (project-owned): `sf_tests_for <path>`
# prints candidate tests for one changed path, `sf_run_tests <files…>` runs them. Only tests
# on disk are kept: a deleted source still picks a surviving test, a deleted test is never
# passed on. Nothing to run → exit 0. Exit: the runner's status; 2 on a usage or setup error
# or an unfilled project.sh stub. Safe under macOS /bin/bash 3.2.
set -euo pipefail

usage() {
	printf 'usage: .superflow/bin/near-tests.sh [--list] [<base>]\n' >&2
	exit 2
}
list=0 base=""
for arg in "$@"; do
	case "$arg" in
	--list) list=1 ;;
	-*) usage ;;
	*) [ -z "$base" ] || usage; base="$arg" ;;
	esac
done

cd "$(git rev-parse --show-toplevel)"
[ -f .superflow/project.sh ] || {
	printf 'error: .superflow/project.sh is missing (the SuperFlow kit'\''s install.sh seeds it)\n' >&2
	exit 2
}
# shellcheck source=/dev/null
. ./.superflow/project.sh
if [ -z "$base" ]; then
	trunk="$(.superflow/bin/fact Trunk)" || exit 2
	base="$(git merge-base HEAD "origin/$trunk")" || {
		printf 'error: git merge-base HEAD origin/%s failed\n' "$trunk" >&2
		exit 2
	}
fi
git rev-parse -q --verify "$base^{commit}" >/dev/null || {
	printf 'error: %s is not a commit\n' "$base" >&2
	exit 2
}
diffed="$(git -c core.quotePath=false diff --name-only --no-renames "$base")" || {
	printf 'error: git diff --name-only %s failed\n' "$base" >&2
	exit 2
}
untracked="$(git -c core.quotePath=false ls-files --others --exclude-standard)" || {
	printf 'error: git ls-files --others failed\n' >&2
	exit 2
}
changed="$(printf '%s\n%s\n' "$diffed" "$untracked" | sort -u)"

nl=$'\n'
picked=""
while IFS= read -r p; do
	[ -n "$p" ] || continue
	out="$(sf_tests_for "$p")" || {
		rc=$?
		printf 'error: sf_tests_for %s failed (exit %s): fix .superflow/project.sh\n' "$p" "$rc" >&2
		exit 2
	}
	while IFS= read -r t; do
		if [ -n "$t" ] && [ -f "$t" ]; then picked="$picked$t$nl"; fi
	done <<EOF
$out
EOF
done <<EOF
$changed
EOF

tests="$(printf '%s' "$picked" | awk 'NF' | sort -u)"
if [ "$list" -eq 1 ]; then
	[ -z "$tests" ] || printf '%s\n' "$tests"
	exit 0
fi
if [ -z "$tests" ]; then
	printf 'near: no tests next to the change set\n'
	exit 0
fi

status=0
set -f
IFS="$nl"
# shellcheck disable=SC2086 # one word per test path
sf_run_tests $tests || status=$?
exit "$status"
