#!/usr/bin/env bash
# check.sh — the fork ledger gate. Reads .fork/CHANGES.md and runs the entries' commands.
#
#   .fork/check.sh                    every entry's Verify, plus the merge=ours pin check
#   .fork/check.sh <slug>...          only those entries' Verifies, exactly as written
#   .fork/check.sh --check <slug>...  those entries' Check commands (a Check of `none` passes)
#
# Prints `ok <slug>`, or `FAIL <slug> (exit <n>)` followed by the command's output, and `SLOW <slug> <n>s`
# for a Verify past two seconds. Exits non-zero if anything failed. A malformed ledger fails: a heading
# that is not `## custom: <slug>`, a duplicate slug, or a missing, repeated or empty field.
# Called by .fork/hooks/pre-commit, .fork/hooks/pre-merge-commit, CI and the upstream-port and fork-change skills.
# Safe for bash 3.2 (the Mac's /bin/bash).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

LEDGER=.fork/CHANGES.md
FIELDS='What it does|Why|Files|Depends on upstream|Tripwire paths|Must still be true|Verify|Check'
SLUG_CHARS=abcdefghijklmnopqrstuvwxyz0123456789-
err=0
bad() { printf 'check.sh: %s\n' "$*" >&2; err=1; }

[ -f "$LEDGER" ] || { bad "$LEDGER is missing"; exit 1; }

# --- parse -------------------------------------------------------------------------------------------
slugs=() verifies=() checks=()
n=-1 seen= fence=0 lineno=0

close_entry() {
  [ "$n" -ge 0 ] || return 0
  local f IFS='|'
  for f in $FIELDS; do
    case "|$seen|" in *"|$f|"*) ;; *) bad "${slugs[$n]}: missing field **$f**" ;; esac
  done
}

while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  case "$line" in '```'*|'~~~'*) fence=$((1 - fence)); continue ;; esac
  [ "$fence" -eq 0 ] || continue
  case "$line" in
    '##'*)
      slug=${line#'## custom: '}
      case "$line" in '## custom: '*) ;; *) slug= ;; esac
      case "$slug" in ''|*[!$SLUG_CHARS]*) bad "line $lineno: heading must be '## custom: <slug>' (a-z, 0-9, -): $line"; continue ;; esac
      for s in ${slugs[@]+"${slugs[@]}"}; do [ "$s" != "$slug" ] || bad "line $lineno: duplicate slug $slug"; done
      close_entry
      n=$((n + 1)); slugs[$n]=$slug; verifies[$n]=; checks[$n]=; seen=
      continue ;;
  esac
  [ "$n" -ge 0 ] || continue # the preamble
  case "$line" in *[![:space:]]*) ;; *) continue ;; esac
  case "$line" in
    '- **'*'** — '*) ;;
    *) bad "line $lineno (${slugs[$n]}): not a field line '- **<Field>** — <value>': $line"; continue ;;
  esac
  rest=${line#'- **'}
  name=${rest%%'** — '*}
  value=${rest#*'** — '}
  case "|$FIELDS|" in *"|$name|"*) ;; *) bad "line $lineno (${slugs[$n]}): unknown field **$name**"; continue ;; esac
  case "|$seen|" in *"|$name|"*) bad "line $lineno (${slugs[$n]}): repeated field **$name**"; continue ;; esac
  seen="$seen|$name"
  case "$value" in *[![:space:]]*) ;; *) bad "line $lineno (${slugs[$n]}): empty field **$name**"; continue ;; esac
  case "$name" in Verify) verifies[$n]=$value ;; Check) checks[$n]=$value ;; esac
done < "$LEDGER"
close_entry
[ "$fence" -eq 0 ] || bad "$LEDGER: unclosed fenced block"
# A ledger with no entries yet (a fresh fork) passes: there is nothing to verify.

# --- run ---------------------------------------------------------------------------------------------
now() { perl -MTime::HiRes=time -e 'printf "%.2f\n", time'; }

run_verify() { # INDEX
  local slug=${slugs[$1]} cmd=${verifies[$1]} t0 out rc secs
  [ -n "$cmd" ] || { echo "FAIL $slug (no Verify)"; err=1; return; }
  t0=$(now)
  out=$(bash -c "$cmd" </dev/null 2>&1); rc=$?
  secs=$(perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' "$t0" "$(now)")
  if [ "$rc" -eq 0 ]; then echo "ok $slug"
  else echo "FAIL $slug (exit $rc)"; [ -z "$out" ] || printf '%s\n' "$out"; err=1; fi
  if perl -e 'exit($ARGV[0] > 2 ? 0 : 1)' "$secs"; then echo "SLOW $slug ${secs}s"; fi
}

run_check() { # INDEX
  local slug=${slugs[$1]} cmd=${checks[$1]} rc
  [ -n "$cmd" ] || { echo "FAIL $slug (no Check)"; err=1; return; }
  if [ "$cmd" = none ]; then echo "none $slug"; return; fi
  bash -c "$cmd" </dev/null; rc=$?
  if [ "$rc" -eq 0 ]; then echo "ok $slug"; else echo "FAIL $slug (exit $rc)"; err=1; fi
}

index_of() { # SLUG → index on stdout, or non-zero
  local i=0
  while [ "$i" -le "$n" ]; do [ "${slugs[$i]}" != "$1" ] || { echo "$i"; return 0; }; i=$((i + 1)); done
  return 1
}

mode=verify
if [ "${1:-}" = --check ]; then
  mode=check; shift
  [ "$#" -gt 0 ] || { bad "usage: .fork/check.sh [--check] <slug>..."; exit 2; }
fi

if [ "$#" -eq 0 ]; then
  i=0; while [ "$i" -le "$n" ]; do run_verify "$i"; i=$((i + 1)); done
  # Every path pinned merge=ours must match a tracked file: a pin on a renamed path silently stops working.
  if [ -f .gitattributes ]; then
    set -f
    while IFS= read -r l || [ -n "$l" ]; do
      case "$l" in ''|'#'*) continue ;; esac
      set -- $l; pat=$1; shift
      for a in "$@"; do
        [ "$a" = merge=ours ] || continue
        case "$pat" in */*) spec=":(glob)${pat#/}" ;; *) spec=":(glob)**/$pat" ;; esac
        [ -n "$(git ls-files -- "$spec")" ] || bad ".gitattributes pins '$pat' merge=ours, but no tracked file matches it"
      done
    done < .gitattributes
    set +f
  fi
else
  for s in "$@"; do
    i=$(index_of "$s") || { bad "unknown slug: $s"; continue; }
    if [ "$mode" = check ]; then run_check "$i"; else run_verify "$i"; fi
  done
fi
exit "$err"
