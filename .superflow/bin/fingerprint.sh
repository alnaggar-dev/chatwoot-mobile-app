#!/usr/bin/env bash
# .superflow/bin/fingerprint.sh — name the code a check ran on.
#
# usage: .superflow/bin/fingerprint.sh
# Prints one sha256 over: HEAD, the working tree's binary diff from it (tracked plus untracked
# non-ignored files, staged through a temporary copy of the index, so staged or not gives the
# same value and the real index and refs never change), and every SF_FINGERPRINT_FILES entry
# that exists (path + bytes; set in .superflow/project.sh, default `.env`). Markdown is left
# out of the diff, so a doc fix does not stale code evidence. Same output ⇔ same code under test.
# Exit: 0 ok, 2 on usage or setup error. Safe under macOS /bin/bash 3.2.
set -euo pipefail

[ "$#" -eq 0 ] || {
	printf 'usage: .superflow/bin/fingerprint.sh (takes no arguments)\n' >&2
	exit 2
}
cd "$(git rev-parse --show-toplevel)"
[ -f .superflow/project.sh ] || {
	printf 'error: .superflow/project.sh is missing (the SuperFlow kit'\''s install.sh seeds it)\n' >&2
	exit 2
}
SF_FINGERPRINT_FILES=".env"
# shellcheck source=/dev/null
. ./.superflow/project.sh

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
}

# A copy of the real index with the whole working tree staged (`git add -A` respects
# .gitignore); the real index and refs are never touched.
windex="$(mktemp "${TMPDIR:-/tmp}/sf-fingerprint-index.XXXXXX")"
trap 'rm -f "$windex" "$windex.lock"' EXIT
real="$(git rev-parse --git-path index)"
# -p keeps the index mtime, so git's racy-clean check still rehashes same-second edits.
if [ -f "$real" ]; then cp -p "$real" "$windex"; else rm -f "$windex"; fi
GIT_INDEX_FILE="$windex" git add -A

{
	git rev-parse HEAD
	GIT_INDEX_FILE="$windex" git diff --cached --binary --no-ext-diff --no-color HEAD -- . ':(exclude)*.md'
	# shellcheck disable=SC2086 # space-separated list; globs allowed
	for f in ${SF_FINGERPRINT_FILES:-}; do
		if [ -f "$f" ]; then
			printf '%s\n' "$f"
			cat -- "$f"
		fi
	done
} | sha256 | awk '{ print $1 }'
