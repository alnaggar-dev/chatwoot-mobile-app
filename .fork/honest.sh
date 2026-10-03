#!/usr/bin/env bash
# honest.sh — the ledger honesty check. Prints every changed upstream-owned path that no .fork/CHANGES.md
# entry's Files matches.
#
#   .fork/honest.sh --cached      the staged change
#   .fork/honest.sh <a> <b>       the change from <a> to <b> (`<sha>^ <sha>`: a commit already made)
#
# The arguments go to `git diff`. Skipped: .fork/, the kit folders, features/, docs/adr/, changelogs, files the
# base (`git merge-base HEAD <upstream>`, the **Upstream** value in .omp/rules/commands.md) lacks (fork-owned),
# and files with no delta left against the base. --no-renames keeps a moved file's upstream path.
# Exit: 0 printed nothing, 1 printed a path, 2 the base or the diff cannot be computed.
# Called by the fork-change skill (step 4) and by .fork/tripwires.sh unregistered (upstream-port step 8).
# Safe for bash 3.2 (the Mac's /bin/bash).

cd "$(git rev-parse --show-toplevel)" || exit 2
upstream=$(.superflow/bin/fact Upstream) || exit 2
b=$(git merge-base HEAD "$upstream") || exit 2
all=$(mktemp) && m=$(mktemp) || exit 2
trap 'rm -f "$all" "$m"' EXIT

git diff "$@" --name-only --no-renames >"$all" || exit 2
sed -n '/^## custom: /,$s/^- \*\*Files\*\* — //p' .fork/CHANGES.md | grep -o '`[^`]*`' | tr -d '`' | sed 's/^/:(glob)/' |
  tr '\n' '\0' | xargs -0 -r git diff "$@" --name-only --no-renames -- | sort -u >"$m"
out=$(sort -u "$all" | comm -23 - "$m" |
  grep -vE '^(\.fork|\.fork-flow|\.superflow|\.omp|features|docs/adr)/|(^|/)CHANGELOG[^/]*$' |
  while IFS= read -r p; do git cat-file -e "$b:$p" 2>/dev/null && ! git diff --quiet "$b" -- "$p" && echo "$p"; done)
[ -z "$out" ] && exit 0
printf '%s\n' "$out"
exit 1
