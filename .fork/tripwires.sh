#!/usr/bin/env bash
# tripwires.sh — the port probe over .fork/CHANGES.md: each entry's Files and Tripwire paths against git.
#
#   .fork/tripwires.sh paths <rev> [<slug>...]       every Tripwire path of the entries (default all) matches a
#                                                    file at <rev>; prints `<slug>\t<path>` per miss
#   .fork/tripwires.sh hits <pointer> <target>        `## <slug>` and its `git log --oneline <pointer>..<target>`
#                                                    lines, for entries whose Files or Tripwire paths upstream touched;
#                                                    a commit whose only change to a `package.json` is its `"version"`
#                                                    line is no hit for that path (releases bump it)
#   .fork/tripwires.sh moved <pointer> <target>       `<slug>\t<status>\t<path>[\t<new path>]` per Files or Tripwire path
#                                                    upstream renamed (R<score>, with the new path) or deleted (D); rename
#                                                    detection runs on the whole tree, so a path renamed out of the globs
#                                                    still shows its new name
#   .fork/tripwires.sh unregistered <port> <target>   paths the fork's delta gained outside every Files since the
#                                                    previous port <last> (the newest `port: ` merge reachable from
#                                                    <port>^1 and not from <upstream>, through a PR merge's second
#                                                    parent too):
#                                                    `comm -13 <(honest.sh <last>^2 <last>) <(honest.sh <target> HEAD)`
#                                                    (honest.sh exit 1 = it printed paths, not a failure); no
#                                                    previous port (the first) → every path `honest.sh <target> HEAD`
#                                                    prints
#   .fork/tripwires.sh unchanged <target>             slugs whose Files no longer differ from <target> (retirement candidates)
#
# <upstream> is the **Upstream** value in .omp/rules/commands.md. Ledger paths are git globs (`*` one directory,
# `**` any depth), passed as `:(glob)<path>` since a plain pathspec misses `a/**/b` matching `a/b`. A Tripwire
# paths value of `none` is skipped. Reads the field lines `- **Files** — ` and `- **Tripwire paths** — `
# (backticked, comma-separated) under `## custom: <slug>` headings.
# Exits 0 clean, 1 a miss (`paths`), 2 usage or git failure.
# Called by the fork-change skill (step 3: `paths "$b" <slugs it wrote>`) and the upstream-port skill (step 8,
# all modes), and by .fork/port-dry-run.sh (`hits`). Safe for bash 3.2 (the Mac's /bin/bash).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

LEDGER=.fork/CHANGES.md
die() { printf 'tripwires.sh: %s\n' "$*" >&2; exit 2; }
usage() { die "usage: .fork/tripwires.sh paths <rev> [<slug>...] | hits|moved|unregistered <a> <b> | unchanged <target>"; }
commit() { git rev-parse -q --verify "$1^{commit}" >/dev/null || die "not a commit: $1"; }
[ -f "$LEDGER" ] || die "$LEDGER is missing"

# One line per ledger path: `<slug>\t<F|T>\t<path>`, fenced blocks skipped.
rows=$(awk '
  /^(```|~~~)/ { fence = !fence; next }
  fence { next }
  /^## custom: / { slug = substr($0, 12); next }
  slug == "" { next }
  /^- \*\*Files\*\* — / { k = "F" }
  /^- \*\*Tripwire paths\*\* — / { k = "T" }
  k != "" {
    v = $0; sub(/^- \*\*[^*]*\*\* — /, "", v)
    while (match(v, /`[^`]*`/)) {
      p = substr(v, RSTART + 1, RLENGTH - 2); v = substr(v, RSTART + RLENGTH)
      if (p != "" && p != "none") printf "%s\t%s\t%s\n", slug, k, p
    }
    k = ""
  }' "$LEDGER") || die "cannot parse $LEDGER"
slugs=$(sed -n 's/^## custom: //p' "$LEDGER")

# specs SLUG KINDS → NUL-separated `:(glob)` pathspecs of that entry's paths of KINDS (F, T or FT).
specs() {
  printf '%s\n' "$rows" | awk -F'\t' -v s="$1" -v k="$2" '$1 == s && index(k, $2) { printf ":(glob)%s%c", $3, 0 }'
}
has_specs() { [ -n "$(specs "$1" "$2" | tr -d '\0')" ]; }

mode=${1:-}; [ "$#" -gt 0 ] && shift
case "$mode" in
  paths)
    [ "$#" -ge 1 ] || usage
    rev=$1; shift; commit "$rev"
    empty=$(git hash-object -t tree /dev/null) || die "cannot build the empty tree"
    [ "$#" -gt 0 ] || set -- $slugs
    miss=0
    for s in "$@"; do
      printf '%s\n' "$slugs" | grep -qxF -- "$s" || die "unknown slug: $s"
      while IFS="$(printf '\t')" read -r _ _ p; do
        [ -n "$p" ] || continue
        out=$(git diff --name-only "$empty" "$rev" -- ":(glob)$p") || die "git diff failed for $p"
        [ -n "$out" ] || { printf '%s\t%s\n' "$s" "$p"; miss=1; }
      done <<EOF
$(printf '%s\n' "$rows" | awk -F'\t' -v s="$s" '$1 == s && $2 == "T"')
EOF
    done
    exit "$miss" ;;
  hits)
    [ "$#" -eq 2 ] || usage
    commit "$1"; commit "$2"
    tab=$(printf '\t')
    # `<sha>\t<package.json path>` per commit whose only change to that file is its "version" line
    vo=$(git log --format=%H "$1..$2" -- ':(glob)**/package.json' | while read -r c; do
      git diff --name-only --no-renames "$c^1" "$c" -- ':(glob)**/package.json' | while IFS= read -r p; do
        d=$(git diff -U0 "$c^1" "$c" -- ":(literal)$p" | grep -E '^[-+]' | grep -vE '^(\+\+\+|---) ')
        if [ -n "$d" ] && ! printf '%s\n' "$d" | grep -qvE '^[-+][[:space:]]*"version":'; then printf '%s\t%s\n' "$c" "$p"; fi
      done
    done) || die "git log failed on $1..$2"
    for s in $slugs; do
      has_specs "$s" FT || continue
      out=$(specs "$s" FT | xargs -0 git log --format='%H %h %s' "$1..$2" --) || die "git log failed for $s"
      out=$(printf '%s\n' "$out" | while read -r c line; do
        [ -n "$c" ] || continue
        if printf '%s\n' "$vo" | grep -q "^$c$tab"; then
          left=$(specs "$s" FT | xargs -0 git diff --name-only --no-renames "$c^1" "$c" -- | while IFS= read -r p; do
            printf '%s\n' "$vo" | grep -qxF "$c$tab$p" || echo "$p"; done)
          [ -n "$left" ] || continue
        fi
        printf '%s\n' "$line"
      done)
      [ -z "$out" ] || printf '## %s\n%s\n' "$s" "$out"
    done ;;
  moved)
    [ "$#" -eq 2 ] || usage
    commit "$1"; commit "$2"
    all=$(git -c core.quotePath=false diff --name-status -M --diff-filter=DR "$1" "$2") || die "git diff failed"
    [ -n "$all" ] || exit 0
    for s in $slugs; do
      has_specs "$s" FT || continue
      # --no-renames lists a renamed path as deleted, so this is every old path the entry's globs match.
      old=$(specs "$s" FT | xargs -0 git -c core.quotePath=false diff --name-only --no-renames --diff-filter=D "$1" "$2" --) ||
        die "git diff failed for $s"
      [ -n "$old" ] || continue
      printf '%s\n' "$all" | OLD="$old" awk -F'\t' -v s="$s" '
        BEGIN { n = split(ENVIRON["OLD"], a, "\n"); for (i = 1; i <= n; i++) o[a[i]] = 1 }
        ($2 in o) { printf "%s\t%s\t%s", s, $1, $2; if (NF >= 3) printf "\t%s", $3; printf "\n" }'
    done ;;
  unregistered)
    [ "$#" -eq 2 ] || usage
    commit "$1"; commit "$2"
    upstream=$(.superflow/bin/fact Upstream) || die "no Upstream value in .omp/rules/commands.md"
    last=$(git log -1 --merges --format=%H --grep='^port: ' "$1^1" --not "$upstream") || die "git log failed on $1^1"
    a=
    if [ -n "$last" ]; then
      a=$(.fork/honest.sh "$last^2" "$last"); [ $? -le 1 ] || die "honest.sh failed on $last"
    else
      echo "tripwires.sh: no previous port merge reachable from $1^1 (first port): every unregistered path counts" >&2
    fi
    b=$(.fork/honest.sh "$2" HEAD); [ $? -le 1 ] || die "honest.sh failed on $2..HEAD"
    comm -13 <(printf '%s\n' "$a" | sort -u) <(printf '%s\n' "$b" | sort -u) | sed '/^$/d' ;;
  unchanged)
    [ "$#" -eq 1 ] || usage
    commit "$1"
    for s in $slugs; do
      has_specs "$s" F || continue
      specs "$s" F | xargs -0 git diff --quiet "$1" HEAD --; rc=$?
      case "$rc" in 0) echo "$s" ;; 1|123) ;; *) die "git diff failed for $s" ;; esac
    done ;;
  *) usage ;;
esac
exit 0
