#!/usr/bin/env bash
# port-letin.sh — upstream-port step 7's let-in list. Prints every staged path outside upstream's own diff,
# labelled with the candidate kind it may be, or `other`.
#
#   .fork/port-letin.sh <pointer> <target>
#
# Staged = `git diff --cached --name-only --no-renames`; upstream's = `git diff --name-only --no-renames
# <pointer> <target>`. Kinds: lockfile (a common lockfile name, or a path .gitattributes marks `!merge`),
# generated (a path or glob the **Regenerate generated files** value in .omp/rules/commands.md names), ledger
# (.fork/), verify program (`scripts/verify-*`, or a path some `- **Verify** — ` line of the working tree's
# .fork/CHANGES.md names as a word). Generator churn and renumbered migrations have no kind of their own: they
# print as `other`. A kind is a candidate only: the skill judges each path (an `other` may still be generator
# churn or a renumbered migration), journals why, and sends anything else to fork-change after the merge.
# Prints only; changes nothing.
# Exit: 0 printed (possibly nothing), 1 git failure, 2 usage.
# Called by the upstream-port skill (step 7). Safe for bash 3.2 (the Mac's /bin/bash).
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: .fork/port-letin.sh <pointer> <target>" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)" || exit 1
s=$(mktemp) && u=$(mktemp) && v=$(mktemp) && g=$(mktemp) || exit 1
trap 'rm -f "$s" "$u" "$v" "$g"' EXIT

# Every word of every Verify line, `./` dropped: the paths the Verifies run or read.
{ sed -n 's/^- \*\*Verify\*\* — //p' .fork/CHANGES.md 2>/dev/null || true; } |
  tr -s " \t'\"\`();|&<>=,\$" '\n' | sed 's#^\./##' | sort -u >"$v"

# The generated paths: `<path> → <command>; …`, the part before each arrow.
gen=$(.superflow/bin/fact 'Regenerate generated files' 2>/dev/null || true)
case "$gen" in none | '') ;; *)
  printf '%s\n' "$gen" | tr ';' '\n' | sed 's/→.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d' >"$g" ;;
esac

git diff --cached -z --name-only --no-renames | tr '\0' '\n' | sort -u >"$s" || exit 1
git diff -z --name-only --no-renames "$1" "$2" | tr '\0' '\n' | sort -u >"$u" || exit 1

generated() { # PATH: matches a generated path or glob (a trailing `/` covers the directory)
  local pat
  while IFS= read -r pat; do
    case "$pat" in */) case "$1" in "$pat"*) return 0 ;; esac ;; esac
    # shellcheck disable=SC2254
    case "$1" in $pat) return 0 ;; esac
  done <"$g"
  return 1
}

comm -23 "$s" "$u" | while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in
    .fork/*) k=ledger ;;
    scripts/verify-*) k='verify program' ;;
    *.lock | *.lockb | *-lock.json | *-lock.yaml | *-lock.yml | *.lock.json | *-shrinkwrap.json | go.sum | */go.sum) k=lockfile ;;
    *)
      if [ "$(git check-attr merge -- "$p" | sed 's/^.*: merge: //')" = unset ]; then k=lockfile
      elif generated "$p"; then k=generated
      elif grep -qxF -- "$p" "$v"; then k='verify program'
      else k=other; fi ;;
  esac
  printf '%s\t%s\n' "$k" "$p"
done
