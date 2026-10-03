#!/usr/bin/env bash
# .superflow/bin/full-suite.sh — run the whole local suite on one commit, away from the checkout.
#
# usage: .superflow/bin/full-suite.sh <sha>
#   Adds a throwaway detached worktree at <sha> (mktemp -d; removed on exit, then
#   `git worktree prune`), copies each existing SF_FINGERPRINT_FILES entry (from
#   .superflow/project.sh, default .env) into it, runs **Install deps** (`none` skips it) and
#   then **Full suite (local)** there, both via `.superflow/bin/fact` and `bash -c`. The checkout
#   (working tree, index, HEAD) is never touched.
# Exit: the suite's status; 2 usage or setup failure (<sha> not a commit, worktree add failed,
# Install deps failed or unreadable) or Full suite (local) `none`/missing/placeholder: the suite
# could not run, which is never green. Safe under macOS /bin/bash 3.2.
set -euo pipefail

die() {
	printf 'full-suite: %s\n' "$1" >&2
	exit 2
}
[ "$#" -eq 1 ] && [ -n "$1" ] || {
	printf 'usage: .superflow/bin/full-suite.sh <sha>\n' >&2
	exit 2
}
root="$(git rev-parse --show-toplevel)" || die "not inside a git repository"
cd "$root"
sha="$(git rev-parse -q --verify "$1^{commit}")" || die "$1 is not a commit"
suite="$(.superflow/bin/fact "Full suite (local)")" || die "could not run: no Full suite (local) in .omp/rules/commands.md"
[ "$suite" != none ] || die "could not run: Full suite (local) is none"
deps="$(.superflow/bin/fact "Install deps")" || die "could not read Install deps from .omp/rules/commands.md"

SF_FINGERPRINT_FILES=".env"
if [ -f .superflow/project.sh ]; then
	# shellcheck source=/dev/null
	. ./.superflow/project.sh
fi

wt="$(mktemp -d)" || die "mktemp failed"
cleanup() {
	git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"
	git -C "$root" worktree prune >/dev/null 2>&1 || true
}
trap cleanup EXIT
git worktree add -q --detach "$wt" "$sha" || die "git worktree add $sha failed"
for f in ${SF_FINGERPRINT_FILES:-}; do
	[ -e "$f" ] || continue
	mkdir -p "$wt/$(dirname "$f")"
	cp -R "$f" "$wt/$f" || die "copying $f into the worktree failed"
done

cd "$wt"
if [ "$deps" != none ]; then
	bash -c "$deps" || die "Install deps failed"
fi
rc=0
bash -c "$suite" || rc=$?
exit "$rc"
