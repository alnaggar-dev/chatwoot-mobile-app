#!/usr/bin/env bash
# .superflow/bin/ship-deploy.sh — the `ship` skill's merge, landing, deploy, promote and cleanup.
#
# usage: .superflow/bin/ship-deploy.sh <command> [args]
#   record k=v...  pr=<N|none> branch=<b|none> head=<40-hex|none> tests=cloud|local|skip|unknown;
#                  also stores base=<origin/<trunk> sha> (not fetched: the trunk the checks ran on).
#                  A record for another pr is dropped; a new record needs all four; a changed
#                  head= clears tests=, with a note unless the same call gives a new tests=.
#   merge <N>      the record is PR N's with head= and base=; local HEAD is head= (else back to
#                  step 4); no tracked edit (else back to step 3); origin/<trunk>, fetched, is
#                  still base= and in head= (else back to step 4). Waits for the PR's checks
#                  (`gh pr checks N --watch --fail-fast`; "no checks reported" is not green:
#                  retried for ~5 minutes, then stop), then fetches origin/<trunk> again: it must
#                  still be base= and in head= (moved during the checks → back to step 4). A repo
#                  with no CI (**Full suite in CI** `none` and no .github/workflows/ in head='s
#                  tree) merges without checks when gh still reports none after one poll. Then
#                  `gh pr merge N --<Merge method> --match-head-commit <head>` (`--merge` in a
#                  fork install), never --admin; refused → back to step 4. Prints `merged: PR #N
#                  at <head>`.
#   land <N|sha>   the landed candidate. PR N must be MERGED into <trunk>; sha = its merge commit
#                  when that is on origin/<trunk> (fetched), else its head (a PR landed by push),
#                  else stop. A bare sha must be on origin/<trunk>; its PR is the one merged PR
#                  into <trunk> whose merge commit or head it is (several → stop; none →
#                  pr=none branch=none head=none). A record for another pr or sha is dropped,
#                  except one whose sha= already holds the candidate (an adopt moved it on):
#                  kept, exit 5. tests= kept only when the PR's head equals the record's head=
#                  and, for a merge commit, <sha>^1 is in that head; `cloud` only when the head's
#                  checks passed the full suite (see below); no record or no tests= → `cloud`
#                  when they did, else `unknown`; pr=none → `unknown`. Writes pr, branch (the
#                  record's when set), head, tests, sha; prints the record and `tests=<v>`.
#   adopt <sha>    the validation environment serves a later trunk commit: <sha> must be on
#                  origin/<trunk> and hold the record's sha (else stop: wait for it, then adopt).
#                  Resolves its PR and tests= as `land <sha>` (another PR's tests= never carry
#                  over), keeps branch=, and prints the files changed from the old sha.
#   deploy         **Deploy** for the record's sha. `none` → prints `nothing deployed: Deploy is
#                  none`, exit 3. `automatic on merge` → watches every Actions run on <trunk>
#                  for the sha (`gh run watch --exit-status`); none, even after a settle wait →
#                  exit 4. A command → when it reaches production (**Promote** `none`) tests=
#                  must be set and not `unknown`; runs it in a throwaway detached worktree at
#                  the sha, **Install deps** first (`none` skips). Prints `deployed: <sha>`.
#   promote        **Promote** (`none` → stop) for the record's sha: tests= set and not
#                  `unknown`; run as `deploy` runs a command. Prints `promoted: <sha>`.
#   done           fetches origin/<trunk>; the record's branch= (none → nothing to delete) must
#                  be merged: fork install or **Merge method** `merge` → its local and remote
#                  tips are in origin/<trunk>; `squash`/`rebase` → its PR is MERGED at head=,
#                  equal to both tips. Then `git switch <trunk>`, `git pull --ff-only` (refused →
#                  stop, never reset), deletes the branch (local, then remote with a lease), the
#                  `feature/<slug>` state dir, and the record. Any failure keeps the record.
#                  Prints `record removed`.
#
# Full suite passed in CI on a PR head: **Full suite in CI** `none` → never; `add label <x>` →
# the PR carries label x; `runs on every PR` → no label needed. Then the key's second value
# (`fact "Full suite in CI" 2`: comma-separated check-run name patterns, `*` matches any text)
# names the full-suite checks: on the head, taking each check name's latest run, every
# pattern matches at least one check, every matching check concluded success (skipped,
# neutral or pending is not green), and no other check failed. No second value → never.
# <trunk> is `.superflow/bin/fact Trunk`; every key comes from .omp/rules/commands.md that way.
# Fork install: .fork/CHANGES.md exists. The record is one line of k=v words (pr branch head
# tests base sha) in $(git rev-parse --git-dir)/superflow/ship, written atomically. Any
# unexpected gh or git result stops with a message: this script never guesses a verdict.
# Env (seconds): SHIP_DEPLOY_POLL between "no checks reported" retries (default 15);
# SHIP_DEPLOY_SETTLE before concluding a push has no Actions run (default 30).
# Exit: 0 ok; 1 stopped with a message (or an unreadable record); 2 usage; 3 deploy: **Deploy**
# is `none`, nothing deployed; 4 deploy: `automatic on merge` and no Actions run for the sha
# (ask the operator: nothing deployable, or deployed outside Actions); 5 land: the record's
# sha= already holds the candidate, record kept (ship resumes at step 6 with it). Messages go
# to stderr, results to stdout. Safe under macOS /bin/bash 3.2.
set -euo pipefail
set -f

POLL=${SHIP_DEPLOY_POLL:-15} SETTLE=${SHIP_DEPLOY_SETTLE:-30}
TRIES=20 # "no checks reported" retries: ~5 minutes at the default poll
HEX40='^[0-9a-f]{40}$'

die() {
	printf 'ship-deploy: %s\n' "$*" >&2
	exit 1
}
bad() {
	printf 'ship-deploy: %s\n' "$*" >&2
	exit 2
}
say() { printf '%s\n' "$@"; }
usage() {
	printf '%s\n' 'usage: .superflow/bin/ship-deploy.sh <command>' \
		'  record pr=<N|none> branch=<b|none> head=<40-hex|none> tests=cloud|local|skip|unknown' \
		'  merge <N> | land <N|sha> | adopt <sha> | deploy | promote | done' >&2
	exit 2
}

TOP=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git work tree"
cd "$TOP"
GITDIR=$(git rev-parse --absolute-git-dir) || die "git rev-parse --absolute-git-dir failed"
REC=$GITDIR/superflow/ship
WT_TMP='' ERRF=''
cleanup() {
	[ -z "$ERRF" ] || rm -f "$ERRF"
	if [ -n "$WT_TMP" ]; then
		git worktree remove --force "$WT_TMP/wt" >/dev/null 2>&1 || true
		rm -rf "$WT_TMP"
		git worktree prune >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT

fact() { "$TOP/.superflow/bin/fact" "$@" || die "cannot read **$1** (.superflow/bin/fact $*)"; }
is_fork() { [ -f .fork/CHANGES.md ]; }
load_trunk() { TRUNK=$(fact Trunk) || exit 1; }
fetch_trunk() {
	load_trunk
	git fetch --quiet --no-tags origin "+refs/heads/$TRUNK:refs/remotes/origin/$TRUNK" ||
		die "git fetch origin $TRUNK failed"
	TIP=$(git rev-parse --verify --quiet "refs/remotes/origin/$TRUNK") || die "no origin/$TRUNK after the fetch"
}
merge_method() {
	if is_fork; then
		METHOD=merge
		return 0
	fi
	METHOD=$(fact "Merge method") || exit 1
	case $METHOD in merge | squash | rebase) ;; *) die "**Merge method** is '$METHOD', not merge, squash or rebase" ;; esac
}
# anc <a> <b>: 0 when <a> is an ancestor of <b>, 1 when not; anything else stops.
anc() {
	local rc=0
	git merge-base --is-ancestor "$1" "$2" 2>/dev/null || rc=$?
	[ "$rc" -le 1 ] || die "git merge-base --is-ancestor $1 $2 failed"
	return "$rc"
}
on_trunk() { git cat-file -e "$1^{commit}" 2>/dev/null && anc "$1" "$TIP"; }

rec_load() {
	R_pr='' R_branch='' R_head='' R_tests='' R_base='' R_sha='' HAVE=''
	[ -e "$REC" ] || return 0
	local line w v
	line=$(cat "$REC") || die "unreadable record $REC"
	HAVE=1
	for w in $line; do
		v=${w#*=}
		case $w in
		pr=*) [[ $v =~ ^[0-9]+$ || $v == none ]] && R_pr=$v ;;
		branch=?*) R_branch=$v ;;
		head=*) [[ $v =~ $HEX40 || $v == none ]] && R_head=$v ;;
		tests=*) [[ $v =~ ^(cloud|local|skip|unknown)$ ]] && R_tests=$v ;;
		base=*) [[ $v =~ $HEX40 ]] && R_base=$v ;;
		sha=*) [[ $v =~ $HEX40 ]] && R_sha=$v ;;
		*) false ;;
		esac || die "unreadable record $REC: '$w'"
	done
}
rec_save() {
	local k n line=''
	for k in pr branch head tests base sha; do
		n=R_$k
		[ -z "${!n}" ] || line="$line${line:+ }$k=${!n}"
	done
	mkdir -p "${REC%/*}" || die "cannot create ${REC%/*}"
	{ printf '%s\n' "$line" >"$REC.tmp.$$" && mv -f "$REC.tmp.$$" "$REC"; } || die "cannot write $REC"
	say "record: $line"
}
rec_drop() {
	say "dropped the record for another candidate: $(cat "$REC")"
	rm -f "$REC"
	rec_load
}
rec_sha() {
	rec_load
	[ -n "$HAVE" ] && [[ $R_sha =~ $HEX40 ]] || die "the record has no sha= (run land first)"
}
tests_gate() {
	case ${R_tests:-unknown} in
	unknown) die "the record has tests=${R_tests:-unset}: $1 needs the local full suite on $R_sha first (step 7)" ;;
	esac
}

# pr_info <N> → P_state P_base P_merge P_ref P_head P_labels; the PR must be merged into <trunk>.
pr_info() {
	local t
	t=$(gh pr view "$1" --json state,baseRefName,mergeCommit,headRefName,headRefOid,labels --jq \
		'[.state, .baseRefName, (.mergeCommit.oid // "-"), .headRefName, .headRefOid, ([.labels[].name] | join(",") | if . == "" then "-" else . end)] | @tsv') ||
		die "gh pr view $1 failed"
	IFS=$'\t' read -r P_state P_base P_merge P_ref P_head P_labels <<EOF
$t
EOF
	[ "$P_state" = MERGED ] && [ "$P_base" = "$TRUNK" ] || die "PR #$1 is $P_state into $P_base, not merged into $TRUNK"
	[[ $P_head =~ $HEX40 ]] || die "PR #$1 has no head sha ('$P_head')"
}
# sha_pr <sha> → pr=<N|none> (P_* set when found).
sha_pr() {
	local prs n
	prs=$(gh api "repos/{owner}/{repo}/commits/$1/pulls" \
		--jq ".[] | select(.merged_at != null and .base.ref == \"$TRUNK\") | .number") || die "PR lookup for $1 failed"
	n=$(printf '%s\n' "$prs" | grep -c . || true)
	case $n in
	0) pr=none ;;
	1)
		[[ $prs =~ ^[0-9]+$ ]] || die "PR lookup for $1 returned '$prs'"
		pr=$prs
		pr_info "$pr"
		[ "$1" = "$P_merge" ] || [ "$1" = "$P_head" ] || die "$1 is neither PR #$pr's merge commit ($P_merge) nor its head ($P_head)"
		;;
	*) die "$1 belongs to several merged PRs: $(printf '%s' "$prs" | tr '\n' ' ')" ;;
	esac
}
# full_check <name>: the name matches a full-suite pattern in $names.
full_check() {
	local IFS=, pat
	for pat in $names; do
		pat="${pat#"${pat%%[![:space:]]*}"}"
		pat="${pat%"${pat##*[![:space:]]}"}"
		# shellcheck disable=SC2254 # the pattern is a glob
		[ -n "$pat" ] && case "$1" in $pat) return 0 ;; esac
	done
	return 1
}
# cloud_ok: the full suite passed in CI on P_head (see the header).
cloud_ok() {
	local ci label runs latest names pat name concl hit bad=0 rc=0
	ci=$(fact "Full suite in CI") || exit 1
	case $ci in
	none) return 1 ;;
	'runs on every PR') ;;
	'add label '?*)
		label=${ci#add label }
		case ",$P_labels," in
		*",$label,"*) ;;
		*)
			say "tests: PR #$pr does not carry label $label: no full suite in CI"
			return 1
			;;
		esac
		;;
	*) die "**Full suite in CI** is '$ci', not runs on every PR, add label <x> or none" ;;
	esac
	names=$(fact "Full suite in CI" 2 2>/dev/null) || rc=$?
	if [ "$rc" != 0 ] || [ "$names" = none ] || [ -z "${names//[, ]/}" ]; then
		say "tests: **Full suite in CI** names no full-suite checks (its second value): no cloud evidence"
		return 1
	fi
	runs=$(gh api "repos/{owner}/{repo}/commits/$P_head/check-runs" --paginate \
		--jq '.check_runs[] | [.id, .name, (.conclusion // "pending")] | @tsv') ||
		die "check-runs lookup for $P_head failed"
	# The latest run of each check name: "<conclusion>\t<name>".
	latest=$(printf '%s\n' "$runs" | sort -t "$(printf '\t')" -k1,1nr | awk -F '\t' 'NF >= 3 && !seen[$2]++ { print $3 "\t" $2 }')
	while IFS=$'\t' read -r concl name; do
		[ -n "$name" ] || continue
		if full_check "$name"; then
			[ "$concl" = success ] || { say "tests: full-suite check '$name' is $concl on $P_head"; bad=1; }
		else
			case $concl in success | neutral | skipped) ;; *) say "tests: check '$name' is $concl on $P_head"; bad=1 ;; esac
		fi
	done <<EOF
$latest
EOF
	local IFS=,
	for pat in $names; do
		pat="${pat#"${pat%%[![:space:]]*}"}"
		pat="${pat%"${pat##*[![:space:]]}"}"
		[ -n "$pat" ] || continue
		hit=0
		while IFS=$'\t' read -r concl name; do
			# shellcheck disable=SC2254 # the pattern is a glob
			[ -n "$name" ] && case "$name" in $pat) hit=1 ;; esac
		done <<EOF
$latest
EOF
		[ "$hit" = 1 ] || { say "tests: no check matching '$pat' on $P_head: the full suite has not run"; bad=1; }
	done
	[ "$bad" = 0 ]
}
# evidence <sha> → E_tests, from R_head/R_tests (the record kept for this candidate) and P_*.
evidence() {
	E_tests=unknown
	if [ "$pr" = none ]; then
		[ -z "$R_tests" ] || say "tests: $1 has no merged PR to tie tests=$R_tests to: dropped"
		return 0
	fi
	if [ -n "$R_tests" ] && [ "$R_head" != "$P_head" ]; then
		say "tests: PR #$pr merged head $P_head, not the recorded head ${R_head:-none}: tests=$R_tests dropped"
		return 0
	fi
	if [ "$1" != "$P_head" ] && ! anc "$1^1" "$P_head"; then
		say "tests: $P_head lacks $1^1 ($TRUNK before the merge): evidence dropped"
		return 0
	fi
	case $R_tests in
	local | skip) E_tests=$R_tests ;;
	*)
		if cloud_ok; then
			E_tests=cloud
		elif [ "$R_tests" = cloud ]; then
			say "tests: no full suite passed in CI on $P_head: cloud dropped"
		fi
		;;
	esac
}

cmd_record() {
	[ $# -gt 0 ] || usage
	local a v pr='' branch='' head='' tests='' tip
	for a in "$@"; do
		v=${a#*=}
		case $a in
		pr=*) [[ $v =~ ^[0-9]+$ || $v == none ]] || bad "pr= takes a PR number or none"; pr=$v ;;
		branch=*) [ "$v" = none ] || git check-ref-format --branch "$v" >/dev/null 2>&1 || bad "bad branch '$v'"; branch=$v ;;
		head=*) [[ $v =~ $HEX40 || $v == none ]] || bad "head= takes a full 40-hex SHA or none"; head=$v ;;
		tests=*) [[ $v =~ ^(cloud|local|skip|unknown)$ ]] || bad "tests= is cloud, local, skip or unknown"; tests=$v ;;
		*) bad "record takes pr=, branch=, head=, tests=" ;;
		esac
	done
	load_trunk
	tip=$(git rev-parse --verify --quiet "refs/remotes/origin/$TRUNK") || die "no origin/$TRUNK in this clone: git fetch origin first"
	rec_load
	if [ -n "$HAVE" ] && [ -n "$pr" ] && [ "$pr" != "$R_pr" ]; then rec_drop; fi
	[ -n "$HAVE" ] || { [ -n "$pr" ] && [ -n "$branch" ] && [ -n "$head" ] && [ -n "$tests" ]; } ||
		die "a new record needs pr=, branch=, head= and tests="
	if [ -n "$head" ] && [ -n "$R_head" ] && [ "$head" != "$R_head" ] && [ -n "$R_tests" ]; then
		[ -n "$tests" ] || say "head moved from $R_head: its tests=$R_tests no longer counts"
		R_tests=''
	fi
	R_pr=${pr:-$R_pr} R_branch=${branch:-$R_branch} R_head=${head:-$R_head} R_tests=${tests:-$R_tests} R_base=$tip
	rec_save
}

# base_ok: origin/<trunk>, fetched now, is still the record's base= and in its head=.
base_ok() {
	fetch_trunk
	[ "$TIP" = "$R_base" ] || die "origin/$TRUNK moved since the checks ($R_base → $TIP): back to step 4"
	anc "$TIP" "$R_head" || die "the tested head $R_head lacks origin/$TRUNK: back to step 4"
}
# wait_checks <N> <tries> → 0 checks passed; 3 gh reported no checks <tries> times; stops on red.
wait_checks() {
	local i=0 rc
	ERRF=$(mktemp) || die "mktemp failed"
	while :; do
		rc=0
		gh pr checks "$1" --watch --fail-fast >&2 2>"$ERRF" || rc=$?
		cat "$ERRF" >&2
		[ "$rc" != 0 ] || return 0
		grep -q 'no checks reported' "$ERRF" || die "PR #$1 checks did not pass"
		i=$((i + 1))
		[ "$i" -lt "$2" ] || return 3
		sleep "$POLL"
	done
}
cmd_merge() {
	[ $# = 1 ] && [[ $1 =~ ^[0-9]+$ ]] || usage
	rec_load
	[ -n "$HAVE" ] || die "no record in $REC: run record first"
	[ "$R_pr" = "$1" ] || die "the record is for PR #${R_pr:-none}, not #$1"
	[[ $R_head =~ $HEX40 && $R_base =~ $HEX40 ]] || die "the record has no head= and base= ($(cat "$REC")): record again"
	local h st ci wf rc=0
	h=$(git rev-parse --verify HEAD) || die "git rev-parse HEAD failed"
	[ "$h" = "$R_head" ] || die "local HEAD $h is not the recorded head $R_head: back to step 4"
	st=$(git status --porcelain --untracked-files=no) || die "git status failed"
	[ -z "$st" ] || die "tracked edits not committed: back to step 3"
	merge_method
	ci=$(fact "Full suite in CI") || exit 1
	base_ok
	wf=$(git ls-tree --name-only "$R_head" .github/workflows/) || die "git ls-tree $R_head failed"
	if [ "$ci" = none ] && [ -z "$wf" ]; then
		wait_checks "$1" 2 || rc=$?
		[ "$rc" != 3 ] || say "no CI (Full suite in CI is none, no .github/workflows/): merging without checks"
	else
		wait_checks "$1" "$TRIES" || rc=$?
		[ "$rc" != 3 ] || die "PR #$1: still no checks reported after $((TRIES * POLL))s; never green: stop and ask"
	fi
	base_ok
	gh pr merge "$1" "--$METHOD" --match-head-commit "$R_head" >&2 || die "gh pr merge $1 refused (the head moved off $R_head?): back to step 4"
	say "merged: PR #$1 at $R_head"
}

cmd_land() {
	[ $# = 1 ] || usage
	fetch_trunk
	rec_load
	local sha head=none branch=none
	if [[ $1 =~ ^[0-9]+$ ]]; then
		pr=$1
		pr_info "$pr"
		if [[ $P_merge =~ $HEX40 ]] && on_trunk "$P_merge"; then
			sha=$P_merge
		elif on_trunk "$P_head"; then
			sha=$P_head
		else
			die "PR #$pr: neither its merge commit ($P_merge) nor its head ($P_head) is on origin/$TRUNK"
		fi
	elif [[ $1 =~ ^[0-9a-f]{4,40}$ ]]; then
		sha=$(git rev-parse --verify --quiet "$1^{commit}") || die "no commit $1 in this clone"
		on_trunk "$sha" || die "$sha is not on origin/$TRUNK"
		sha_pr "$sha"
	else
		usage
	fi
	[ "$pr" = none ] || { head=$P_head branch=$P_ref; }
	if [ -n "$HAVE" ] && { [ "$R_pr" != "$pr" ] || { [ -n "$R_sha" ] && [ "$R_sha" != "$sha" ]; }; }; then
		if [[ $R_sha =~ $HEX40 ]] && git cat-file -e "$R_sha^{commit}" 2>/dev/null && anc "$sha" "$R_sha"; then
			printf 'ship-deploy: %s\n' "the record's sha=$R_sha (PR #${R_pr:-none}) already holds $sha (an adopt moved the candidate on); record kept: resume at ship step 6, never land again" >&2
			exit 5
		fi
		rec_drop
	fi
	evidence "$sha"
	R_pr=$pr R_branch=${R_branch:-$branch} R_head=$head R_tests=$E_tests R_sha=$sha
	rec_save
	say "tests=$R_tests"
}

cmd_adopt() {
	[ $# = 1 ] && [[ $1 =~ ^[0-9a-f]{4,40}$ ]] || usage
	fetch_trunk
	rec_sha
	local sha old=$R_sha files
	sha=$(git rev-parse --verify --quiet "$1^{commit}") || die "$1 is not in this clone, so not on origin/$TRUNK yet: wait for it, then adopt"
	on_trunk "$sha" || die "$sha is not on origin/$TRUNK: wait for it, then adopt"
	anc "$old" "$sha" || die "$sha lacks the record's sha $old: wait for a deploy that holds it, then adopt"
	sha_pr "$sha"
	if [ "$pr" != "$R_pr" ]; then
		[ -z "$R_tests" ] || say "tests: the record's tests=$R_tests were PR #$R_pr's: dropped"
		R_tests='' R_head=''
	fi
	evidence "$sha"
	if [ "$pr" = none ]; then R_head=none; else R_head=$P_head; fi
	R_pr=$pr R_branch=${R_branch:-none} R_tests=$E_tests R_sha=$sha
	rec_save
	say "tests=$R_tests"
	files=$(git -c core.quotePath=false diff --name-only "$old" "$sha") || die "git diff $old $sha failed"
	say "files changed from $old to $sha (re-check what they need):"
	[ -z "$files" ] || printf '%s\n' "$files"
}

# run_at_sha <Key> <command>: Install deps, then <command>, in a throwaway detached worktree at R_sha.
run_at_sha() {
	local deps
	deps=$(fact "Install deps") || exit 1
	git cat-file -e "$R_sha^{commit}" 2>/dev/null || die "commit $R_sha is not in this clone"
	WT_TMP=$(mktemp -d) || die "mktemp -d failed"
	git worktree add --quiet --detach "$WT_TMP/wt" "$R_sha" >&2 || die "git worktree add at $R_sha failed"
	if [ "$deps" != none ]; then
		(cd "$WT_TMP/wt" && bash -c "$deps") >&2 || die "Install deps failed in the worktree at $R_sha"
	fi
	(cd "$WT_TMP/wt" && bash -c "$2") >&2 || die "$1 failed for $R_sha"
}
# watch_runs: every Actions run on <trunk> for R_sha must succeed; none → exit 4.
list_runs() {
	gh run list --branch "$TRUNK" --commit "$R_sha" --json databaseId,status,conclusion,name \
		--jq '.[] | "\(.databaseId)\t\(.name)"' || die "gh run list for $R_sha failed"
}
watch_runs() {
	local runs id name
	runs=$(list_runs) || exit 1
	if [ -z "$runs" ]; then
		sleep "$SETTLE"
		runs=$(list_runs) || exit 1
	fi
	if [ -z "$runs" ]; then
		say "no Actions run on $TRUNK for $R_sha after ${SETTLE}s: nothing deployable, or deployed outside Actions; ask the operator"
		exit 4
	fi
	while IFS=$'\t' read -r id name <&3; do
		[[ $id =~ ^[0-9]+$ ]] || die "gh run list returned run id '$id'"
		gh run watch "$id" --exit-status >&2 || die "run $id ($name) for $R_sha did not succeed"
	done 3<<EOF
$runs
EOF
}
cmd_deploy() {
	[ $# = 0 ] || usage
	rec_sha
	local dep promote
	dep=$(fact Deploy) || exit 1
	case $dep in
	none)
		say "nothing deployed: Deploy is none"
		exit 3
		;;
	'automatic on merge')
		load_trunk
		watch_runs
		;;
	*)
		promote=$(fact Promote) || exit 1
		[ "$promote" != none ] || tests_gate "a Deploy that reaches production"
		run_at_sha Deploy "$dep"
		;;
	esac
	say "deployed: $R_sha"
}
cmd_promote() {
	[ $# = 0 ] || usage
	rec_sha
	local p
	p=$(fact Promote) || exit 1
	[ "$p" != none ] || die "Promote is none: nothing to promote (Deploy is production)"
	tests_gate Promote
	run_at_sha Promote "$p"
	say "promoted: $R_sha"
}

cmd_done() {
	[ $# = 0 ] || usage
	rec_load
	[ -n "$HAVE" ] || die "no record in $REC: nothing to finish"
	fetch_trunk
	local b=${R_branch:-none} loc='' rem='' rc=0 st slug
	METHOD=merge
	if [ "$b" != none ]; then
		merge_method
		loc=$(git rev-parse --verify --quiet "refs/heads/$b") || loc=''
		git ls-remote --exit-code --heads origin "refs/heads/$b" >/dev/null || rc=$?
		case $rc in
		0)
			git fetch --quiet --no-tags origin "refs/heads/$b" || die "git fetch origin $b failed; record kept"
			rem=$(git rev-parse --verify FETCH_HEAD) || die "git rev-parse FETCH_HEAD failed; record kept"
			;;
		2) ;;
		*) die "git ls-remote origin $b failed; record kept" ;;
		esac
		if [ "$METHOD" = merge ]; then
			[ -z "$loc" ] || anc "$loc" "$TIP" || die "$b ($loc) is not merged into origin/$TRUNK; record kept"
			[ -z "$rem" ] || anc "$rem" "$TIP" || die "origin's $b ($rem) is not merged into origin/$TRUNK; record kept"
		elif [ -n "$loc$rem" ]; then
			[[ $R_pr =~ ^[0-9]+$ ]] || die "no pr= in the record to prove $b merged; record kept"
			st=$(gh pr view "$R_pr" --json state,headRefOid --jq '"\(.state) \(.headRefOid)"') || die "gh pr view $R_pr failed; record kept"
			[ "$st" = "MERGED $R_head" ] || die "PR #$R_pr is '$st', not MERGED at the recorded head $R_head; record kept"
			[ -z "$loc" ] || [ "$loc" = "$R_head" ] || die "$b ($loc) is not the merged head $R_head; record kept"
			[ -z "$rem" ] || [ "$rem" = "$R_head" ] || die "origin's $b ($rem) is not the merged head $R_head; record kept"
		fi
	fi
	git switch --quiet "$TRUNK" || die "git switch $TRUNK failed; record kept"
	git pull --quiet --ff-only origin "$TRUNK" || die "git pull --ff-only refused; record kept, never reset: stop and ask"
	if [ -n "$loc" ]; then
		if [ "$METHOD" = merge ]; then
			git branch -d "$b" >&2 || die "git branch -d $b refused; record kept"
		else
			git branch -D "$b" >&2 || die "git branch -D $b failed; record kept"
		fi
	fi
	if [ -n "$rem" ]; then
		git push --quiet --force-with-lease="refs/heads/$b:$rem" origin --delete "$b" ||
			die "git push origin --delete $b failed (it moved off $rem?); record kept"
	fi
	case $b in
	feature/*)
		slug=${b#feature/}
		case $slug in
		'' | .* | */*) say "kept the state of $b: '$slug' is not a plain slug" ;;
		*) rm -rf "$GITDIR/superflow/$slug" ;;
		esac
		;;
	esac
	rm -f "$REC"
	say "record removed"
}

case ${1:-} in
record | merge | land | adopt | deploy | promote | done)
	c=$1
	shift
	"cmd_$c" "$@"
	;;
*) usage ;;
esac
