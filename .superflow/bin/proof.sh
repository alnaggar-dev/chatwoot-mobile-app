#!/usr/bin/env bash
# .superflow/bin/proof.sh — review and proof mechanics: which code was checked and reviewed.
#
# usage: .superflow/bin/proof.sh tree | patch-id | stamp <slug> before|after | verdict <file> --head|--fingerprint
#   tree                         git tree id of the working tree (tracked plus untracked
#                                non-ignored files); the real index and refs are untouched.
#   patch-id                     `git patch-id --stable` of the change set since
#                                `git merge-base HEAD origin/<trunk>` (<trunk> is
#                                `.superflow/bin/fact Trunk`), working tree included, Markdown
#                                left out. No merge-base or no change → exit 1.
#   stamp <slug> before          start $(git rev-parse --git-dir)/superflow/<slug>/verify/report.md
#                                (old one replaced): `Commit: <HEAD>`, `Fingerprint-before: <fp>`.
#   stamp <slug> after           write `Fingerprint-after: <fp>` under Fingerprint-before:; exit 1
#                                if it or HEAD moved since before (start again from verify step 1).
#   verdict <file> --head        check the file's last `## Final review` block: `Reviewed:` must be
#                                HEAD, and no uncommitted code outside Markdown.
#   verdict <file> --fingerprint check the file's block from its last `Reviewed:` line to EOF:
#                                `Reviewed:` must be the current fingerprint.
# <fp> is `.superflow/bin/fingerprint.sh`. Review block: `Reviewed: <value>`, optional
# `Patch-id: <hex>`, `Verdict: approve|request changes`, then
# `- Critical|Important|Minor: <finding> (<path>:<line>[-<line>])` lines; blank lines ignored.
# Exit: 0 ok (verdict: approve for the current code); 1 failed or refused (verdict: well-formed
# `request changes`); 2 usage or setup error; 3 verdict malformed; 4 verdict missing,
# `Reviewed:` not current, or (--head) uncommitted code. Safe under macOS /bin/bash 3.2.
set -euo pipefail

usage='usage: .superflow/bin/proof.sh tree | patch-id | stamp <slug> before|after | verdict <file> --head|--fingerprint'
die_usage() {
	printf 'error: %s\n%s\n' "$1" "$usage" >&2
	exit 2
}

cmd="${1:-}"
[ "$#" -eq 0 ] || shift
case "$cmd" in
tree | patch-id)
	[ "$#" -eq 0 ] || die_usage "$cmd takes no arguments"
	;;
stamp)
	[ "$#" -eq 2 ] || die_usage "stamp takes <slug> before|after"
	slug="$1" when="$2"
	case "$slug" in '' | */* | .*) die_usage "bad slug: $slug" ;; esac
	case "$when" in before | after) ;; *) die_usage "stamp takes before or after, not: $when" ;; esac
	;;
verdict)
	[ "$#" -eq 2 ] || die_usage "verdict takes <file> --head|--fingerprint"
	vfile="$1"
	case "$2" in --head) vmode=head ;; --fingerprint) vmode=fingerprint ;; *) die_usage "verdict takes --head or --fingerprint, not: $2" ;; esac
	case "$vfile" in '') die_usage "verdict takes a file" ;; /*) ;; *) vfile="$PWD/$vfile" ;; esac
	;;
'') die_usage "missing command" ;;
*) die_usage "unknown command: $cmd" ;;
esac

cd "$(git rev-parse --show-toplevel)"

# A copy of the index with the whole working tree staged (`git add -A` respects .gitignore), in
# $windex; the real index and refs are never touched.
stage_tree() {
	local real
	if [ -z "${windex:-}" ]; then
		windex="$(mktemp "${TMPDIR:-/tmp}/sf-proof-index.XXXXXX")"
		trap 'rm -f "$windex" "$windex.lock"' EXIT
	fi
	real="$(git rev-parse --git-path index)"
	# -p keeps the index mtime, so git's racy-clean check still rehashes same-second edits.
	if [ -f "$real" ]; then cp -p "$real" "$windex"; else rm -f "$windex"; fi
	GIT_INDEX_FILE="$windex" git add -A
}

fingerprint() {
	.superflow/bin/fingerprint.sh || {
		printf 'error: .superflow/bin/fingerprint.sh failed\n' >&2
		exit 2
	}
}

work_tree() {
	stage_tree
	GIT_INDEX_FILE="$windex" git write-tree
}

# The value after `$1:` on the first such line of file $2, surrounding space trimmed.
stamp_value() {
	awk -v l="$1:" 'index($0, l) == 1 { v = substr($0, length(l) + 1); sub(/^[ \t]+/, "", v); sub(/[ \t\r]+$/, "", v); print v; exit }' "$2"
}

stamp() {
	local dir report head fp commit before
	dir="$(git rev-parse --git-dir)/superflow/$slug/verify"
	report="$dir/report.md"
	head="$(git rev-parse HEAD)"
	fp="$(fingerprint)"
	if [ "$when" = before ]; then
		mkdir -p "$dir"
		printf 'Commit: %s\nFingerprint-before: %s\n' "$head" "$fp" >"$report"
		printf 'stamped %s: Commit: %s, Fingerprint-before: %s\n' "$report" "$head" "$fp"
		return 0
	fi
	[ -f "$report" ] || { printf 'error: no %s: run .superflow/bin/proof.sh stamp %s before\n' "$report" "$slug" >&2; exit 1; }
	before="$(stamp_value Fingerprint-before "$report")"
	commit="$(stamp_value Commit "$report")"
	if [ -z "$before" ] || [ -z "$commit" ]; then
		printf 'error: %s has no Commit: or Fingerprint-before: line: start again from verify step 1\n' "$report" >&2
		exit 1
	fi
	# Replace any Fingerprint-after: line; the new one sits right under Fingerprint-before:.
	awk -v fp="$fp" '/^Fingerprint-after:/ { next } { print } /^Fingerprint-before:/ && !done { print "Fingerprint-after: " fp; done = 1 }' \
		"$report" >"$report.tmp"
	mv "$report.tmp" "$report"
	if [ "$commit" != "$head" ]; then
		printf 'error: HEAD is %s, Commit: says %s: start again from verify step 1\n' "$head" "$commit" >&2
		exit 1
	fi
	if [ "$fp" != "$before" ]; then
		printf 'error: Fingerprint-after: %s differs from Fingerprint-before: %s: start again from verify step 1\n' "$fp" "$before" >&2
		exit 1
	fi
	printf 'ok: %s: Fingerprint-after: matches Fingerprint-before:, HEAD unchanged\n' "$report"
}

# Reads the review block (mode head: the last `## Final review` section up to the next `## `
# heading; mode fingerprint: from the last `Reviewed:` line to EOF). Prints `<Reviewed value> <verdict>`;
# else the reason, exit 3 (malformed) or 4 (missing).
verdict_awk='
function fail(code, msg) { print msg; exit code }
{ sub(/[ \t\r]+$/, "") }
mode == "head" {
	if ($0 == "## Final review") { found = 1; insec = 1; n = 0; next }
	if ($0 ~ /^## /) insec = 0
	if (insec) block[++n] = $0
	next
}
{ line[++all] = $0; if ($0 ~ /^Reviewed:/) last = all }
END {
	if (mode == "head") {
		if (!found) fail(4, "no ## Final review section")
	} else {
		if (!last) fail(4, "no Reviewed: line")
		n = 0
		for (i = last; i <= all; i++) block[++n] = line[i]
	}
	state = 0
	for (i = 1; i <= n; i++) {
		l = block[i]
		if (l == "") continue
		if (state == 0) {
			if (l !~ /^Reviewed:/) {
				for (j = i; j <= n; j++) if (block[j] ~ /^Reviewed:/) fail(3, "first line is not Reviewed:, got: " l)
				fail(4, "no Reviewed: line in ## Final review")
			}
			reviewed = l
			sub(/^Reviewed:[ \t]*/, "", reviewed)
			if (reviewed !~ /^[^ \t]+$/) fail(3, "garbled line: " l)
			state = 1
		} else if (state == 1 && l ~ /^Patch-id:/) {
			if (l !~ /^Patch-id:[ \t]+[0-9a-f]+$/) fail(3, "garbled line: " l)
			state = 2
		} else if (state < 3) {
			if (l ~ /^Verdict:[ \t]+approve$/) verdict = "approve"
			else if (l ~ /^Verdict:[ \t]+request changes$/) verdict = "request changes"
			else fail(3, "expected Verdict: approve or Verdict: request changes, got: " l)
			state = 3
		} else if (l ~ /^- (Critical|Important|Minor): .+ [(][^ ()]+:[0-9]+(-[0-9]+)?[)]$/) {
			if (l !~ /^- Minor:/) serious++
		} else fail(3, "not a finding line - Critical|Important|Minor: <finding> (<path>:<line>), got: " l)
	}
	if (state == 0) fail(4, "no Reviewed: line in ## Final review")
	if (state < 3) fail(3, "no Verdict: line")
	if (verdict == "approve" && serious) fail(3, "Verdict: approve with " serious " Critical or Important finding(s)")
	if (verdict == "request changes" && !serious) fail(3, "Verdict: request changes with no Critical or Important finding")
	print reviewed " " verdict
}
'

verdict() {
	local out st=0 reviewed v now what=HEAD
	[ -f "$vfile" ] || { printf 'error: no file %s\n' "$vfile" >&2; exit 4; }
	out="$(awk -v mode="$vmode" "$verdict_awk" "$vfile")" || st=$?
	if [ "$st" -ne 0 ]; then
		case "$st" in 3 | 4) ;; *) st=4 ;; esac
		printf 'error: %s: %s\n' "$vfile" "${out:-could not read it}" >&2
		exit "$st"
	fi
	reviewed="${out%% *}"
	v="${out#* }"
	if [ "$vmode" = head ]; then
		now="$(git rev-parse HEAD)"
	else
		now="$(fingerprint)"
		what="fingerprint (.superflow/bin/fingerprint.sh)"
	fi
	if [ "$reviewed" != "$now" ]; then
		printf 'error: %s: Reviewed: %s is not the current %s (%s): review again\n' "$vfile" "$reviewed" "$what" "$now" >&2
		exit 4
	fi
	if [ "$vmode" = head ]; then
		out="$(git --no-optional-locks status --porcelain --untracked-files=all -- ':(exclude)*.md')"
		if [ -n "$out" ]; then
			printf 'error: %s: uncommitted code since the review: commit it, then prove and review again\n%s\n' "$vfile" "$out" >&2
			exit 4
		fi
	fi
	if [ "$v" = "request changes" ]; then
		printf 'error: %s: Verdict: request changes: fix the Critical and Important findings, then review once more\n' "$vfile" >&2
		exit 1
	fi
	printf 'ok: Verdict: approve for the current %s\n' "$what"
}

# The change set since the merge-base, staged through $windex.
patch_id() {
	local trunk base id
	trunk="$(.superflow/bin/fact Trunk)" || exit 2
	base="$(git merge-base HEAD "origin/$trunk")" || { printf 'error: no merge-base of HEAD and origin/%s\n' "$trunk" >&2; exit 1; }
	stage_tree
	id="$(GIT_INDEX_FILE="$windex" git diff --cached --binary --no-ext-diff --no-color "$base" -- . ':(exclude)*.md' |
		git patch-id --stable | awk '{ print $1 }')"
	[ -n "$id" ] || { printf 'error: no change since the merge-base %s (Markdown left out)\n' "$base" >&2; exit 1; }
	printf '%s\n' "$id"
}

case "$cmd" in
tree) work_tree ;;
stamp) stamp ;;
verdict) verdict ;;
patch-id) patch_id ;;
esac
