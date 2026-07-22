#!/usr/bin/env bash
# .fork/port.sh — the upstream PORT driver (see Fork Maintenance in your AGENTS.md).
#
#   ./.fork/port.sh init [--force] <sha> [upstream-ref]  set the pointer (--force: sanctioned re-target)
#   ./.fork/port.sh list [upstream-ref]                  the unported backlog, oldest first
#   ./.fork/port.sh plan [--range <sha|tag>] [ref]       FORECAST the backlog read-only: per-commit
#                                                        conflict prediction + registry flags
#   ./.fork/port.sh next [upstream-ref]                  port the OLDEST unported commit
#   ./.fork/port.sh one <sha> [upstream-ref]             port a specific upstream commit (must be the next unported one)
#   ./.fork/port.sh pick <sha> [upstream-ref]            EARLY: cherry-pick one unported commit out of order
#                                                        WITHOUT advancing the pointer (security fast path;
#                                                        Fork-Flow-Early trailer — register it immediately)
#   ./.fork/port.sh run [--until <ref>] [--limit <N>]    BATCH: port until backlog end/--until/--limit,
#                       [--no-lockfile-auto] [ref]       pausing only on conflicts and registry-touching
#                                                        commits; per-commit gates are SCOPED, the batch
#                                                        end runs verify.sh --scoped and journals ONE entry
#                                                        (--until/--no-lockfile-auto persist across a
#                                                        pause-resume; --limit is per-invocation)
#   ./.fork/port.sh range <sha|tag> [upstream-ref]       CATCH-UP: squash-port pointer..<sha> as ONE gated commit
#   ./.fork/port.sh revert [<sha>]                       un-port the NEWEST port (rewinds the pointer, gated)
#   ./.fork/port.sh land [--dry-run] [--no-checks] [<pr>] fast-forward the PR base branch to the PR's TESTED
#                                                        head SHA (requires gh; non-force SHA-addressed push)
#   ./.fork/port.sh continue                             finalize a paused port/unport after resolving conflicts
#   ./.fork/port.sh abort                                throw away an in-progress port/unport (a run batch stays resumable)
#   ./.fork/port.sh status [--porcelain]                 show in-progress state (including an open run batch)
#
# This is the one place the porting INVARIANTS are enforced as code, not skill prose:
#   - every port is a `git cherry-pick -x --no-commit` (a MERGE adds `-m 1`, replaying the
#     merge's first-parent diff — its whole net effect — as one commit); a clean port stays
#     a real commit the integration gate can see — a bare cherry-pick runs NO hook;
#   - the pointer advances in the SAME commit, recorded as `<sha> <ref>` in .fork/UPSTREAM;
#   - the commit carries a strict `Fork-Flow-Port: <full-sha>` trailer (the SOLE signal
#     audit/propose-upstream use to tell a port from your own work — a stray pointer in
#     an ordinary commit is NOT a port);
#   - the pointer only ever moves FORWARD (the new sha must have the old pointer as an
#     ancestor on the upstream line), so it can't silently rewind; `init --force` is the
#     ONE sanctioned reset (upstream force-push / retarget): it commits a fresh Init
#     trailer that audit treats as the start of a new port sequence — never hand-edit;
#   - ports are CONTIGUOUS: only the OLDEST unported commit may be ported (`one <sha>`
#     refuses a later one), so the pointer can't jump PAST unported ancestors and bury
#     them from the backlog/audit;
#   - upstream MERGE commits are ported as a UNIT via `cherry-pick -m 1` — their
#     first-parent diff carries all merged (farm) content AND any evil-merge resolution
#     that lives in no single commit, and the merge SHA stays on the first-parent line;
#   - a fork that fell releases BEHIND can squash-port per release tag with `range` —
#     one gated commit integrating the whole pointer..<sha> span (one conflict set per
#     file), trailered Fork-Flow-Port + Fork-Flow-Port-From. It cherry-picks ONE
#     synthetic commit (the span's end tree parented on the pointer), so the SAME
#     merge machinery as per-commit ports runs: rename detection, merge=ours +
#     mergiraf drivers, rerere, native delete-involved/add-add conflicts;
#   - on conflict it STOPS and points you at conflict-context.sh, then `continue`;
#   - rerere may pre-fill a remembered resolution, but never silently: autoUpdate is
#     forced off and the pause banner flags replayed paths for review (list_conflicts);
#   - a CONFLICTED port (and every range/conflicted revert) appends a journal skeleton
#     to .fork/PORTS.md in the same commit — the conflict set is on record even when
#     nobody journals by hand;
#   - port/unport commits run with FORK_FLOW_PORT=1 in the environment so a CHAINED
#     project hook (formatters!) can skip rewriting them; if one rewrites anyway, the
#     committed tree differs from the staged snapshot and port.sh WARNS after the fact.
#   - `run` batches the SAME per-commit ports (each still its own trailered, gated,
#     individually revertible commit): clean picks flow without stopping; the loop
#     pauses on a real conflict OR a clean pick whose staged paths touch registry
#     entries (the "dangerous clean apply"). Per-commit gates are SCOPED to each
#     commit's own staged paths (FORK_FLOW_GATE_SCOPE — verify.sh reads the env var
#     itself, the hook chain merely inherits it); the batch end re-runs the FULL
#     registry plus every touched entry's Test: (verify.sh --scoped) and journals
#     ONE fact entry in .fork/PORTS.md, so nothing is pushed on scoped checks alone;
#   - `plan` forecasts conflicts/flags read-only via chained git merge-tree
#     (needs git ≥ 2.40 for --merge-base; PROBED, never version-parsed — older git
#     degrades to registry flags only);
#   - conflicted LOCKFILES in run/range are auto-resolved (upstream's side + the
#     ecosystem's own re-resolve, then staged) unless --no-lockfile-auto or
#     FORK_FLOW_NO_LOCKFILE_AUTO=1 — a hand-merged lockfile only ever LOOKS right.
# The actual gate (verify.sh --registry; scoped per commit during a run batch) still
# runs in the pre-commit hook on the final commit; this driver just makes the
# mechanics correct and hard to get wrong.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# shellcheck source=/dev/null
. .fork/lib.sh

state="$(git rev-parse --git-path fork-flow-port 2>/dev/null)"
unport_state="$(git rev-parse --git-path fork-flow-unport 2>/dev/null)"
changes_file=".fork/UPSTREAM"
# Batch (`run`) state: facts accumulate across pauses/continues until the batch
# finishes (backlog end / --until / --limit), then finish_run verifies, journals,
# and clears them. All under .git so a clone never ships half a batch.
run_state="$(git rev-parse --git-path fork-flow-run 2>/dev/null)"
run_touched_file="$(git rev-parse --git-path fork-flow-run-touched 2>/dev/null)"
scope_tmp_file="$(git rev-parse --git-path fork-flow-scope 2>/dev/null)"
# Machine-readable pause state for agent consumers (the banners are for humans):
# written at every pause exit (kind=conflict|registry + sha= + files=/entries=),
# removed by finalize/finalize_early/finalize_unport/cmd_abort. Read it via
# $(git rev-parse --git-path fork-flow-pause) instead of scraping banner prose.
pause_file="$(git rev-parse --git-path fork-flow-pause 2>/dev/null)"
run_mode=0 # set by cmd_run around start_port; finalize/start_port branch on it
lockauto=1 # --no-lockfile-auto sets 0; FORK_FLOW_NO_LOCKFILE_AUTO=1 also disables

die() {
	printf 'port.sh: %s\n' "$*" >&2
	exit 1
}

write_pause_file() { # <kind: conflict|registry> <full-sha> <key: files|entries> <;-joined values>
	printf 'kind=%s\nsha=%s\n%s=%s\n' "$1" "$2" "$3" "$4" >"$pause_file"
}
note() { printf 'port.sh: %s\n' "$*" >&2; }

# rerere is active when rerere.enabled says so, or is unset while .git/rr-cache
# exists (git's own activation rule). Only then is `git rerere remaining`
# meaningful for splitting the conflict listing below.
rerere_active() {
	case "$(git config --get --type=bool rerere.enabled 2>/dev/null || true)" in
	true) return 0 ;;
	false) return 1 ;;
	esac
	[ -d "$(git rev-parse --git-path rr-cache)" ]
}

# Print the unmerged paths to stderr, separating the ones rerere ALREADY auto-
# resolved in the worktree (unmerged in the index but absent from `git rerere
# remaining`). A replayed file carries NO conflict markers, so a reflexive
# `git add` would sweep a remembered — possibly WRONG — resolution through
# unreviewed; the split forces eyes on exactly those paths. Every mutating
# command here runs with rerere.autoUpdate forced off, so a replayed path stays
# unmerged and this listing cannot miss one.
list_conflicts() {
	local p unmerged remaining eligible replayed=""
	# quotepath=false: `git rerere remaining` prints raw bytes while diff would
	# quote non-ASCII paths ("p\303\244.js"), breaking the membership test below
	# (a raw conflict would then masquerade as auto-resolved — verified by hand).
	unmerged="$(git -c core.quotepath=false diff --name-only --diff-filter=U)"
	# Only a full THREE-WAY content conflict (stages 1 AND 2 AND 3 in the index) can
	# have been replayed by rerere here. Delete-involved conflicts and add/add — incl.
	# the synthetic ones a `range` stages — are invisible to `git rerere remaining`,
	# so the bare unmerged-minus-remaining subtraction would mislabel them
	# AUTO-RESOLVED when nothing resolved anything (an add/add with no markers looked
	# exactly like a replay on a machine with global rerere.enabled=true — found by
	# test t54). Under-claiming is safe — a real replay then lists as a plain conflict
	# and still gets reviewed; over-claiming is the lie this banner must never tell.
	eligible="$(git -c core.quotepath=false ls-files -u | awk -F'\t' '
		$1 ~ / 1$/ {s1[$2]=1} $1 ~ / 2$/ {s2[$2]=1} $1 ~ / 3$/ {s3[$2]=1}
		END {for (f in s1) if ((f in s2) && (f in s3)) print f}')"
	remaining="$unmerged"
	if rerere_active; then
		remaining="$(git rerere remaining 2>/dev/null)" || remaining="$unmerged"
	fi
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		if ! printf '%s\n' "$eligible" | grep -Fxq -- "$p"; then
			printf '  %s\n' "$p" >&2 # delete-involved: rerere can never have touched it
		elif printf '%s\n' "$remaining" | grep -Fxq -- "$p"; then
			printf '  %s\n' "$p" >&2
		else
			replayed="${replayed}  ${p}
"
		fi
	done <<EOF
$unmerged
EOF
	if [ -n "$replayed" ]; then
		{
			printf 'rerere AUTO-RESOLVED these from a PAST resolution (no conflict markers, left\n'
			printf 'unmerged on purpose) — REVIEW each one; a remembered fix can be wrong here:\n'
			printf '%s' "$replayed"
			printf 'Redo from scratch:  git rerere forget <file> && git checkout -m -- <file>\n'
		} >&2
	fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# The mechanically-resolvable lockfile set and each one's OWN re-resolver. The
# command must regenerate the file from the manifest — never a full build.
is_lockfile() {
	case "${1##*/}" in
	package-lock.json | npm-shrinkwrap.json | pnpm-lock.yaml | yarn.lock | bun.lock | bun.lockb | Cargo.lock | poetry.lock | uv.lock | Gemfile.lock | composer.lock) return 0 ;;
	*) return 1 ;;
	esac
}
lockfile_regen_cmd() {
	case "${1##*/}" in
	package-lock.json | npm-shrinkwrap.json) printf 'npm install' ;;
	pnpm-lock.yaml) printf 'pnpm install' ;;
	yarn.lock) printf 'yarn install' ;;
	bun.lock | bun.lockb) printf 'bun install' ;;
	Cargo.lock) printf 'cargo metadata --format-version 1 >/dev/null' ;;
	poetry.lock) printf 'poetry lock --no-update' ;;
	uv.lock) printf 'uv lock' ;;
	Gemfile.lock) printf 'bundle lock' ;;
	composer.lock) printf 'composer update --lock --no-interaction' ;;
	esac
}

# First matching .fork/REGEN rule's command for path $1 (or nothing). Rules:
# <path-glob><whitespace><command...>; comment/blank lines ignored. Matching uses
# lib.sh's glob_match — literal equality first, then shell glob, the same order
# verify.sh applies to Touches anchors. First matching rule wins. Always returns
# 0 so `cmd="$(regen_rule_cmd …)"` never trips set -e.
regen_rule_cmd() { # <path>
	[ -f .fork/REGEN ] || return 0
	local pat cmd
	while IFS=$'\t' read -r pat cmd; do
		[ -z "$pat" ] && continue
		if glob_match "$pat" "$1"; then
			printf '%s' "$cmd"
			return 0
		fi
	done <<EOF
$(awk '/^[[:space:]]*#/ {next} NF>=2 {pat=$1; sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/,""); print pat "\t" $0}' .fork/REGEN)
EOF
	return 0
}

# Mechanically resolve conflicted GENERATED files — the built-in LOCKFILE set plus
# the project's own .fork/REGEN rules: take upstream's side, re-run the file's own
# regenerator so YOUR state re-expresses on top, stage. This is the recipe the
# skill used to walk the operator through by hand — a hand-merged lockfile only
# ever LOOKS right. Prints each resolved path on stdout (for banners/state).
# Leaves alone: every conflict matching neither table, a matched path with no
# upstream side (delete-involved), a missing resolver binary, and — on ANY regen
# failure — every file it had taken (conflicts restored via checkout -m; the
# index stages are still present because nothing was staged yet). Opt-out:
# --no-lockfile-auto / FORK_FLOW_NO_LOCKFILE_AUTO=1 (the regen runs
# project-controlled code — same trust class as a registry Verify).
auto_resolve_lockfiles() {
	[ "${lockauto:-1}" = 1 ] || return 0
	[ -n "${FORK_FLOW_NO_LOCKFILE_AUTO:-}" ] && return 0
	local p cmd log rc
	local files=() cmds=()
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		if is_lockfile "$p"; then
			cmd="$(lockfile_regen_cmd "$p")"
			[ -z "$cmd" ] && continue
			if ! have_cmd "${cmd%% *}"; then
				note "lockfile $p: resolver '${cmd%% *}' not on PATH — leaving the conflict for manual resolution"
				continue
			fi
		else
			cmd="$(regen_rule_cmd "$p")"
			[ -z "$cmd" ] && continue
		fi
		if ! git checkout --theirs -- "$p" 2>/dev/null; then
			note "lockfile $p: no upstream side (delete-involved) — leaving for manual resolution"
			continue
		fi
		files+=("$p")
		case " ${cmds[*]-} " in
		*" $cmd "*) : ;;
		*) cmds+=("$cmd") ;;
		esac
	done <<EOF
$(git -c core.quotepath=false diff --name-only --diff-filter=U)
EOF
	[ "${#files[@]}" -eq 0 ] && return 0
	log="$(mktemp)"
	for cmd in "${cmds[@]}"; do
		note "lockfile: re-resolving via '$cmd'"
		rc=0
		bash -c "$cmd" </dev/null >"$log" 2>&1 || rc=$?
		if [ "$rc" -ne 0 ]; then
			note "lockfile regen '$cmd' FAILED (rc=$rc; log: $log) — restoring the conflict(s) for manual resolution"
			for p in "${files[@]}"; do git checkout -m -- "$p" 2>/dev/null || true; done
			return 0
		fi
	done
	rm -f "$log"
	for p in "${files[@]}"; do
		git add -- "$p"
		printf '%s\n' "$p"
	done
	return 0
}

# Print (to stderr) up to 3 commits linked to registry entry heading $1 via the
# Fork-Flow-Change slug trailer — the resolution-context artifact: the resolving
# agent gets the customization's OWN commits without path archaeology. Headings
# are "custom: <slug>" (a bare slug also accepted); a slug outside
# change_commits_for_slug's charset silently gets no origin lines (legacy slugs).
entry_origin_commits() { # <entry-heading>
	local slug shas s
	slug="${1#custom: }"
	shas="$(change_commits_for_slug "$slug" 2>/dev/null || true)"
	[ -z "$shas" ] && return 0
	printf '%s\n' "$shas" | awk 'NR<=3' | while IFS= read -r s; do
		[ -n "$s" ] && git log -1 --format='      origin: %h %s' "$s" >&2
	done
	return 0
}

# Banner helper: which registry entries does the CURRENT pick touch (staged +
# still-unmerged paths)? Printed at a run-batch conflict pause so the operator
# drift-checks those entries while already in the file — one pause, both jobs.
conflict_registry_note() {
	local pl entries e
	pl="$(
		{
			git -c core.quotepath=false diff --cached --name-only
			git -c core.quotepath=false diff --name-only --diff-filter=U
		} | awk 'NF && !seen[$0]++'
	)"
	entries="$(registry_entries_for_paths "$pl")"
	if [ -n "$entries" ]; then
		printf 'Registry entries touched by this commit (drift-check while resolving):\n' >&2
		printf '%s\n' "$entries" | while IFS= read -r e; do
			[ -z "$e" ] && continue
			printf '  - %s\n' "$e" >&2
			entry_origin_commits "$e"
		done
	fi
	return 0
}

ptr_ref_default() { upstream_pointer_ref; }

require_clean_tree() {
	if ! git diff --quiet || ! git diff --cached --quiet; then
		die "working tree is dirty — commit or stash first (a port must start clean)"
	fi
}

# Gate-wiring detection (a fresh clone has no hooks until ./.fork/setup.sh runs
# there) lives in lib.sh as hooks_gate_wired — shared with verify.sh's post-install
# unwire warning so the two can never disagree.

# Defense in depth: when the hooks are NOT wired, run the integration gate INLINE
# before the port/unport commit — otherwise a fresh clone would port UNGATED, the
# exact silent-customization-drop the kit exists to prevent. When the hooks ARE
# wired, the pre-commit hook runs the same check and this stays out of the way (no
# double run). Honors the hooks' FORK_SKIP_VERIFY escape.
inline_gate() { # <what: port|unport>
	[ -n "${FORK_SKIP_VERIFY:-}" ] && return 0
	hooks_gate_wired && return 0
	[ -x .fork/verify.sh ] || return 0
	note "hooks not wired in this clone — running the gate inline (wire them: ./.fork/setup.sh)"
	if ! ./.fork/verify.sh --registry; then
		die "gate FAILED — a customization may not have survived this $1.
       Fix it, then ./.fork/port.sh continue   (or abort). One-off bypass: FORK_SKIP_VERIFY=1"
	fi
}

# Per-clone wiring check, run at the start of every MUTATING subcommand (decides
# nothing — warns). git config is not carried by copied files, so on a fresh clone
# the hooks and the merge=ours driver are silently off: the inline gate keeps
# port.sh commits safe regardless, but manual commits/merges are ungated, and
# merge=ours paths would not hold during ports.
preflight() {
	if ! hooks_gate_wired; then
		note "WARNING: fork-flow hooks are not wired in this clone — port.sh runs its gate"
		note "         inline, but MANUAL commits/merges are ungated. Wire them once:"
		note "         ./.fork/setup.sh   (shipped with the fork; --check reports wiring)"
	fi
	if [ -n "$(merge_ours_paths)" ] && ! git config merge.ours.driver >/dev/null 2>&1; then
		note "WARNING: .gitattributes declares merge=ours paths but merge.ours.driver is not"
		note "         configured in this clone — those overrides will NOT hold during ports."
		note "         Fix: ./.fork/setup.sh   (or git config merge.ours.driver true)"
	fi
}

# Write "<sha> <ref>" to .fork/UPSTREAM, preserving the file's comment header.
write_pointer() { # <full-sha> <ref>
	local sha="$1" ref="$2" tmp
	tmp="$(mktemp)"
	# keep every comment/blank line from the existing header; drop the old SHA line
	if [ -f "$changes_file" ]; then
		awk 'NF==0 || $1 ~ /^#/ {print}' "$changes_file" >"$tmp"
	fi
	printf '%s %s\n' "$sha" "$ref" >>"$tmp"
	mv "$tmp" "$changes_file" || { rm -f "$tmp"; return 1; }
}

# Refuse to move the pointer backwards or sideways: the new commit must be a
# descendant of the current pointer (forward-only on the upstream line).
assert_forward() { # <new-sha>
	local newsha="$1" cur
	cur="$(upstream_pointer)"
	[ -z "$cur" ] && return 0
	[ "$cur" = "$newsha" ] && return 0
	if ! git merge-base --is-ancestor "$cur" "$newsha" 2>/dev/null; then
		die "refusing to move pointer to $newsha: current pointer $cur is not its ancestor
       (that would rewind or sidestep the pointer — port in order, or fix .fork/UPSTREAM)"
	fi
}

# Port-time refusal of a pointer that no reachable IN-EFFECT port trailer backs:
# audit only WARNS about a hand-edited .fork/UPSTREAM, so porting kept building on
# the lie until someone read the audit. Called by run/next/one/range/pick before
# touching the tree — NOT by init (init is the fix) or revert (it has its own
# stricter trailer search). Cost: effective_port_trailer_sha stops at the first
# in-effect trailer — O(commits since the last port) in practice.
assert_pointer_trailer_consistent() {
	local ptr eff tr
	ptr="$(upstream_pointer)"
	[ -z "$ptr" ] && return 0
	eff="$(effective_port_trailer_sha)"
	if [ -z "$eff" ]; then
		die "pointer is set ($(git rev-parse --short "$ptr" 2>/dev/null || printf '%s' "$ptr")) but NO reachable in-effect $PORT_TRAILER trailer backs it —
       hand-edited .fork/UPSTREAM? Inspect with ./.fork/audit.sh; the one sanctioned
       reset is ./.fork/port.sh init --force <sha> [ref]"
	fi
	tr="${eff#* }"
	if [ "$(git rev-parse "$tr" 2>/dev/null)" != "$(git rev-parse "$ptr" 2>/dev/null)" ]; then
		die "pointer file ($(git rev-parse --short "$ptr" 2>/dev/null || printf '%s' "$ptr")) does not match the newest in-effect port trailer ($(git rev-parse --short "$tr" 2>/dev/null || printf '%s' "$tr")) —
       .fork/UPSTREAM edited after the last port? Inspect with ./.fork/audit.sh; if the
       re-target is sanctioned, reset with ./.fork/port.sh init --force <sha> [ref]"
	fi
}

resolve_upstream_ref() { # [arg]
	local ref="${1:-}"
	if [ -z "$ref" ]; then ref="$(ptr_ref_default)"; fi
	if [ -z "$ref" ]; then ref="upstream/main"; fi
	git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1 ||
		die "not a commit: $ref (fetch upstream, or pass the right ref)"
	printf '%s' "$ref"
}

backlog() { # <upstream-ref>
	local ref="$1" base
	base="$(upstream_base "$ref")" || exit $? # hard-fails (3) on a broken pointer
	git log --first-parent --reverse --format='%H' "$base..$ref"
}

cmd_status() {
	# --porcelain: stable key=value lines for agent consumers; prose otherwise.
	if [ "${1:-}" = "--porcelain" ]; then
		local st_kind="idle" st_file="" st_early=0
		if [ -f "$state" ]; then
			st_kind=port
			st_file="$state"
			grep -q '^EARLY=1$' "$state" 2>/dev/null && st_early=1
		elif [ -f "$unport_state" ]; then
			st_kind=unport
			st_file="$unport_state"
		fi
		printf 'state=%s\n' "$st_kind"
		printf 'early=%s\n' "$st_early"
		printf 'run=%s\n' "$([ -f "$run_state" ] && echo open || echo none)"
		if [ -n "$st_file" ]; then
			awk -F= '/^SHA=/{print "sha=" $2} /^UNPORT=/{print "sha=" $2} /^REF=/{print "ref=" $2} /^FROM=/{print "from=" $2}' "$st_file"
		fi
		if [ -f "$run_state" ]; then
			awk -F= '/^UNTIL=/{print "until=" $2}' "$run_state"
		fi
		printf 'pointer=%s\n' "$(upstream_pointer)"
		return 0
	fi
	if [ -f "$state" ]; then
		printf 'A port is IN PROGRESS:\n'
		sed 's/^/  /' "$state"
		printf 'Resolve conflicts, then: ./.fork/port.sh continue   (or: ./.fork/port.sh abort)\n'
	elif [ -f "$unport_state" ]; then
		printf 'An UNPORT (revert) is IN PROGRESS:\n'
		sed 's/^/  /' "$unport_state"
		printf 'Resolve conflicts, then: ./.fork/port.sh continue   (or: ./.fork/port.sh abort)\n'
	else
		printf 'No port in progress. Pointer: %s (ref %s)\n' \
			"$(upstream_pointer || echo '(unset)')" "$(upstream_pointer_ref || echo '?')"
	fi
	if [ -f "$run_state" ]; then
		printf 'A RUN batch is open (started %s):\n' "$(awk -F= '/^DATE=/{print $2; exit}' "$run_state")"
		printf '  ported so far: %s (+%s empty); pauses: %s; lockfile auto-resolves: %s\n' \
			"$(grep -c '^PORT=' "$run_state" || true)" "$(grep -c '^EMPTY=' "$run_state" || true)" \
			"$(grep -c '^PAUSE=' "$run_state" || true)" "$(grep -c '^LOCKAUTO=' "$run_state" || true)"
		printf '  finish or resume: ./.fork/port.sh run\n'
	fi
}

cmd_list() {
	local ref list n=0 sha
	ref="$(resolve_upstream_ref "${1:-}")"
	# Capture via command substitution (NOT process substitution): backlog's
	# upstream_base hard-fails (exit 3) on a corrupt pointer, and that must propagate
	# under set -e. A `done < <(backlog …)` would run backlog in a subshell whose exit
	# the parent never sees, so a broken pointer would print "(up to date)" — the exact
	# silent lie the pointer contract forbids (cmd_next already captures this way).
	list="$(backlog "$ref")"
	printf '== unported backlog (%s), oldest first ==\n' "$ref"
	while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		printf '  %s  %s\n' "$(git rev-parse --short "$sha")" "$(git log -1 --format=%s "$sha")"
		n=$((n + 1))
	done <<EOF
$list
EOF
	[ "$n" -eq 0 ] && printf '  (up to date)\n'
	[ "$n" -gt 0 ] && printf '  -> %d to port; run ./.fork/port.sh next\n' "$n"
	return 0 # success regardless of backlog size (corrupt pointer already exited 3 above)
}

cmd_init() {
	local force=0
	if [ "${1:-}" = "--force" ]; then
		force=1
		shift
	fi
	local sha="${1:-}" ref="${2:-upstream/main}" old old_ref
	[ -n "$sha" ] || die "usage: ./.fork/port.sh init [--force] <upstream-sha> [upstream-ref]"
	[ -f "$state" ] && die "a port is in progress — finish it (continue/abort) first"
	[ -f "$unport_state" ] && die "an unport is in progress — finish it (continue/abort) first"
	old="$(upstream_pointer)"
	old_ref="$(upstream_pointer_ref)"
	if [ -n "$old" ] && [ "$force" -eq 0 ]; then
		die "pointer already set ($old); init is one-time only.
       To RE-TARGET after an upstream force-push or branch switch (the recorded pointer
       no longer sits on the line you port from), reset it explicitly — with the user's
       agreement, never silently:   ./.fork/port.sh init --force <sha> [ref]
       A forced re-init commits a fresh $INIT_TRAILER trailer, which audit treats
       as a sanctioned sequence reset; hand-editing .fork/UPSTREAM is flagged as tamper."
	fi
	require_clean_tree
	preflight
	git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1 || die "not a commit: $sha"
	sha="$(git rev-parse "$sha")"
	git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1 || die "not a commit: $ref"
	# A forced re-init records WHY in the commit (the old pointer), and its Init trailer
	# is what audit's port-order check recognizes as the start of a new port sequence.
	local subject body
	if [ -n "$old" ]; then
		subject="fork-flow: re-initialize upstream pointer (forced)"
		body="Sanctioned pointer RESET (upstream force-push / retarget): the previous pointer
$old${old_ref:+ ($old_ref)} no longer sits on the line being ported. No code is
ported by this commit; audit treats this Init trailer as the start of a new port
sequence, and subsequent ports advance from here."
	else
		subject="fork-flow: initialize upstream pointer"
		body="Records the upstream commit this fork last corresponded to. No code is ported by
this commit; subsequent ports advance the pointer one upstream commit at a time."
	fi
	# init ports NO code, so it is NOT an integration — commit with --no-verify.
	# Staging .fork/UPSTREAM otherwise trips the pre-commit integration gate, which
	# would block init on an unrelated red/prose Verify even though nothing was ported.
	# Snapshot the pointer file first so a commit that still fails for another reason
	# (e.g. signing) rolls back cleanly, instead of leaving a staged-but-uncommitted
	# pointer that makes the retry die with "pointer already set".
	local snap had=0
	snap="$(mktemp)"
	if [ -f "$changes_file" ]; then
		cp "$changes_file" "$snap"
		had=1
	fi
	# Until the commit lands, restore the snapshot on ANY failure — not just a failed
	# `git commit`. write_pointer or `git add` failing (e.g. a stale .git/index.lock)
	# would otherwise abort under set -e with the pointer already staged/written, so the
	# retry dies with "pointer already set". Track rc explicitly so set -e never
	# short-circuits past the rollback.
	local rc=0
	write_pointer "$sha" "$ref" || rc=$?
	[ "$rc" = 0 ] && { git add "$changes_file" || rc=$?; }
	# --allow-empty: a sanctioned re-init to the very SHA a hand-edit already wrote
	# changes no file — the INIT TRAILER commit is still required (it is what the
	# port-time consistency gate and audit accept as the reset).
	[ "$rc" = 0 ] && { git commit --no-verify --allow-empty -m "$subject

$body

$INIT_TRAILER: $sha" || rc=$?; }
	if [ "$rc" != 0 ]; then
		git reset -q -- "$changes_file" >/dev/null 2>&1 || true
		if [ "$had" -eq 1 ]; then cp "$snap" "$changes_file"; else rm -f "$changes_file"; fi
		rm -f "$snap"
		die "init failed (rc $rc) — pointer change rolled back; nothing committed"
	fi
	rm -f "$snap"
	if [ -n "$old" ]; then
		note "pointer RE-initialized at $sha (ref $ref; was $old)"
	else
		note "pointer initialized at $sha (ref $ref)"
	fi
}

# Stage the pointer + the applied tree and make the final port commit. Shared by a
# clean port and by `continue` after a manual resolve. With a non-empty <from-sha>
# (a `range` catch-up, see cmd_range) the commit message records the squashed span
# instead of one upstream commit and carries a Fork-Flow-Port-From trailer alongside
# the Fork-Flow-Port one (the strict port parser does not match -From, so audit and
# the hooks treat a range commit exactly like any other port).
finalize() { # <full-sha> <ref> [<from-sha>]
	local sha="$1" ref="$2" from="${3:-}" msg subject n conflicts="" lockauto="" jsub staged_tree was_empty=0 run_flag=0 staged_paths=""
	# No unmerged paths may remain.
	if git ls-files --unmerged --error-unmatch -- . >/dev/null 2>&1; then
		list_conflicts
		die "unresolved conflicts remain (above) — resolve + 'git add', then ./.fork/port.sh continue"
	fi
	# Empty pick (upstream change already present)? Decided BEFORE the pointer is
	# staged — run-batch bookkeeping wants honest PORT= vs EMPTY= counts.
	if git diff --cached --quiet && git diff --quiet; then was_empty=1; fi
	assert_forward "$sha"
	write_pointer "$sha" "$ref"
	git add "$changes_file"
	# Journal skeleton (.fork/PORTS.md): a CONFLICTED port and every `range` catch-up
	# get an entry in the SAME commit — the conflict set is on record even when nobody
	# journals by hand (re-porting after a revert otherwise redoes the registry surgery
	# from memory: rerere replays the code, nothing replays the decisions). The
	# "(fill in)" lines are the prompt; the upstream-port skill says to flesh them out.
	# Trivial clean ports are skipped — one noise line per port would drown the journal.
	# JOURNALED= guards a gate-failed retry from appending a duplicate entry.
	if [ -f "$state" ] && ! grep -q '^JOURNALED=1$' "$state" && ! grep -q '^RUN=1$' "$state"; then
		conflicts="$(awk '/^CONFLICT=/{print substr($0,10)}' "$state")"
		lockauto="$(awk '/^LOCKAUTO=/{print substr($0,10)}' "$state")"
		if [ -n "$from" ] || [ -n "$conflicts" ] || [ -n "$lockauto" ]; then
			if [ -n "$from" ]; then
				jsub="catch-up $(git rev-parse --short "$from")..$(git rev-parse --short "$sha") ($ref)"
			else
				jsub="ported $(git rev-parse --short "$sha") \"$(git log -1 --format=%s "$sha")\""
			fi
			{
				printf '\n## %s — %s\n' "$(date +%Y-%m-%d)" "$jsub"
				if [ -n "$conflicts" ]; then
					printf 'Conflicts:\n'
					printf '%s\n' "$conflicts" | while IFS= read -r c; do
						[ -n "$c" ] && printf '  - %s — resolution: (fill in)\n' "$c"
					done
				else
					printf 'Conflicts: none\n'
				fi
				if [ -n "$lockauto" ]; then
					printf 'Lockfile/regen auto-resolves (upstream side + re-resolve):\n'
					printf '%s\n' "$lockauto" | while IFS= read -r c; do
						[ -n "$c" ] && printf '  - %s\n' "$c"
					done
				fi
				printf 'Decisions: (fill in — drift verdicts, merge=ours notes, registry updates)\n'
			} >>.fork/PORTS.md
			git add .fork/PORTS.md
			printf 'JOURNALED=1\n' >>"$state"
		fi
	fi
	if [ -n "$from" ]; then
		n="$(git rev-list --first-parent --count "$from..$sha")"
		msg="$(printf 'port: catch-up %s..%s (%s)\n\nSquash-ports %s upstream first-parent commits as one unit (./.fork/port.sh range).\nPer-commit upstream history for this span: git log %s..%s\n\n%s: %s\n%s: %s\n' \
			"$(git rev-parse --short "$from")" "$(git rev-parse --short "$sha")" "$ref" \
			"$n" "$from" "$sha" "$PORT_TRAILER" "$sha" "$FROM_TRAILER" "$from")"
	else
		subject="$(git log -1 --format=%s "$sha")"
		msg="$(printf '%s\n\n%s\n\n(cherry picked from commit %s)\n%s: %s\n' \
			"$subject" "$(git log -1 --format=%b "$sha")" "$sha" "$PORT_TRAILER" "$sha")"
	fi
	# Run-batch bookkeeping + SCOPED gate: during a `run` each commit's gate is
	# narrowed to the entries this port ENGAGED WITH — its staged paths UNION the
	# upstream commit's own first-parent paths. Staged-only would under-scope the
	# one case that matters most: a conflict resolved by REJECTING upstream's
	# change ends with an empty staged diff (pointer only), yet the customization
	# it defends is exactly what must be verified. Conversely a resolution that
	# touched extra files WIDENS the gate instead of escaping it. verify.sh reads
	# the env var itself; the hook chain simply inherits it through git commit.
	if [ -f "$state" ] && grep -q '^RUN=1$' "$state"; then
		run_flag=1
		staged_paths="$({
			git -c core.quotepath=false diff --cached --name-only
			git -c core.quotepath=false diff-tree -r -m --first-parent --no-commit-id --name-only "$sha" 2>/dev/null
		} | awk 'NF && !seen[$0]++')"
		printf '%s\n' "$staged_paths" >"$scope_tmp_file"
		export FORK_FLOW_GATE_SCOPE="$scope_tmp_file"
	fi
	# The pre-commit integration gate runs verify.sh --registry here (pointer is
	# staged); on an unwired clone inline_gate runs the SAME check right now instead.
	inline_gate port
	# FORK_FLOW_PORT=1 marks this commit for CHAINED project hooks: a formatter hook
	# (eslint --fix + git add, rubocop -a) that rewrites a port commit makes the ported
	# content stop matching upstream — projects can guard their hooks on this variable.
	# The write-tree snapshot detects exactly that rewrite, after the fact.
	staged_tree="$(git write-tree)"
	printf '%s' "$msg" | FORK_FLOW_PORT=1 git commit -F -
	if [ "$run_flag" = 1 ]; then
		unset FORK_FLOW_GATE_SCOPE
		printf '%s\n' "$staged_paths" | awk 'NF' >>"$run_touched_file"
		if [ "$was_empty" = 1 ]; then
			printf 'EMPTY=%s\n' "$sha" >>"$run_state"
		else
			printf 'PORT=%s\n' "$sha" >>"$run_state"
		fi
	fi
	rm -f "$state" "$pause_file"
	warn_if_hook_rewrote "$staged_tree"
	note "ported $sha; pointer now $sha"
}

# A hook ran `git add` during the commit (chained formatters do): the committed tree
# no longer matches what port.sh staged, so the ported content differs from upstream —
# future conflicts get noisier and audit's patch-id hints degrade. Warn, never undo:
# the project's hook may be enforcing something it has every right to enforce.
warn_if_hook_rewrote() { # <staged-tree-oid>
	[ -n "$1" ] || return 0
	[ "$(git rev-parse 'HEAD^{tree}' 2>/dev/null)" = "$1" ] && return 0
	note "WARNING: a hook REWROTE this commit while it was being made (a chained"
	note "         formatter running eslint --fix / rubocop -a + git add?). The committed"
	note "         tree differs from what port.sh staged, so the ported content no longer"
	note "         matches upstream — future conflicts and audit's patch-id hints degrade."
	note "         See what the hook changed:  git diff $1 HEAD"
	note "         Port commits run with FORK_FLOW_PORT=1 set — have the project's hooks"
	note "         skip rewriting when it is present."
}

# Commit an EARLY pick (cmd_pick): the upstream commit's content lands gated, but
# the pointer does NOT move and no Fork-Flow-Port trailer is written — the
# Fork-Flow-Early trailer records the exact upstream SHA so the later contiguous
# catch-up recognizes the (empty) re-port. Mirrors finalize's unmerged check,
# inline gate, FORK_FLOW_PORT=1 marking, and hook-rewrite detection; skips
# everything pointer-related (write_pointer/assert_forward/journal skeleton).
finalize_early() { # <full-sha>
	local sha="$1" msg staged_tree
	if git ls-files --unmerged --error-unmatch -- . >/dev/null 2>&1; then
		list_conflicts
		die "unresolved conflicts remain (above) — resolve + 'git add', then ./.fork/port.sh continue"
	fi
	msg="$(printf '%s\n\n%s\n\n(cherry picked from commit %s)\n%s: %s\n' \
		"$(git log -1 --format=%s "$sha")" "$(git log -1 --format=%b "$sha")" "$sha" "$EARLY_TRAILER" "$sha")"
	inline_gate port
	staged_tree="$(git write-tree)"
	# --allow-empty: an already-present pick still commits the Fork-Flow-Early
	# trailer — the machine attribution catch-up dedupes on must exist either way.
	if git diff --cached --quiet && git diff --quiet; then
		note "early pick of $sha is EMPTY (already present in your fork) — committing the trailer only"
		printf '%s' "$msg" | FORK_FLOW_PORT=1 git commit --allow-empty -F -
	else
		printf '%s' "$msg" | FORK_FLOW_PORT=1 git commit -F -
	fi
	rm -f "$state" "$pause_file"
	warn_if_hook_rewrote "$staged_tree"
	note "picked $sha EARLY — pointer unchanged. Register it now (fork-change skill) with"
	note "Reason naming the upstream commit; when the pointer reaches it the port will land empty."
}

start_port() { # <full-sha> <ref>
	local sha="$1" ref="$2" parents rc oldest lockres="" rentries e
	[ -f "$state" ] && die "a port is already in progress — continue/abort it first"
	[ "$sha" = "$(upstream_pointer)" ] && die "$sha is already the pointer — nothing to port"
	require_clean_tree
	preflight
	# The tamper refusal must precede assert_forward: a sideways pointer would
	# otherwise die with the generic forward-order error and hide the audit /
	# init --force recovery path. cmd_run already checked once per invocation.
	if [ "$run_mode" != 1 ]; then
		assert_pointer_trailer_consistent
	fi
	assert_forward "$sha"
	# Merge commits are ported as a UNIT (see cherry-pick below): a merge's first-parent
	# diff is its entire net effect on the mainline — every second-parent (farm) commit it
	# brought in PLUS any evil-merge resolution that exists in no single commit. Replaying
	# the merged commits one-by-one would miss that resolution; the merge SHA also stays on
	# the first-parent line, so the forward-only pointer never wedges.
	parents="$(git rev-list --parents -n1 "$sha" | awk '{print NF-1}')"
	# Contiguity: the pointer means "everything up to here is ported", so a port may not
	# SKIP commits — start_port applies only the OLDEST unported commit on the ref. This is
	# what stops `one <later-sha>` from advancing the pointer PAST unported ancestors (they
	# would vanish from the backlog though never applied). `next` always passes the oldest,
	# so this only ever bites an out-of-order `one`. (Backward SHAs already died above.)
	# Skipped under `run`: cmd_run just read this SHA off the head of the very backlog
	# it iterates, so recomputing it here made a long catch-up O(N^2).
	# awk NR==1, NEVER `head -1`: head closes the pipe after one line, `git log` takes
	# SIGPIPE once the backlog outgrows the pipe buffer (a few hundred real commits), and
	# set -e turns that into a silent exit 141 — the front door dying with zero output
	# exactly when the fork is most behind (found on a 251-commit real backlog). awk
	# drains stdin to EOF, so the writer always finishes.
	if [ "$run_mode" != 1 ]; then
		oldest="$(backlog "$ref" | awk 'NR==1')"
		if [ "$sha" != "$oldest" ]; then
			[ -z "$oldest" ] && die "$sha is not the next unported commit on $ref (nothing unported there — off-target?)"
			die "refusing to port $sha out of order: the next unported commit on $ref is
       $(git rev-parse --short "$oldest")  $(git log -1 --format=%s "$oldest")
       The pointer is contiguous — port in order with ./.fork/port.sh next (it picks this
       commit), or pass that SHA. To take a single upstream commit early WITHOUT advancing
       the pointer (a security fix that can't wait): ./.fork/port.sh pick $sha"
		fi
	fi
	# Early-pick dedupe: an exact-SHA Fork-Flow-Early trailer means this commit's
	# content already landed via `pick` — the port will (correctly) come up empty.
	if git log --format='%H' -n1 --grep="^${EARLY_TRAILER}: ${sha}\$" HEAD | grep -q .; then
		note "this commit was picked early ($EARLY_TRAILER) — expect an empty port"
	fi
	# Record state BEFORE touching the tree so abort/continue always have it. RUN=1
	# marks a `run`-batch port: finalize then scopes the gate, accumulates touched
	# paths, counts PORT=/EMPTY=, and skips the per-port journal skeleton (the run
	# writes ONE fact entry at its end instead).
	if [ "$run_mode" = 1 ]; then
		printf 'SHA=%s\nREF=%s\nRUN=1\n' "$sha" "$ref" >"$state"
	else
		printf 'SHA=%s\nREF=%s\n' "$sha" "$ref" >"$state"
	fi
	rc=0
	# A merge is replayed against its first parent (-m 1); a normal commit as-is. Both use
	# -x (record the source SHA) and --no-commit (finalize stages the pointer + gates).
	# rerere.autoUpdate (user/global config) would silently STAGE any remembered
	# resolution: the replayed file leaves the unmerged set unreviewed, and a fully-
	# remembered conflict set leaves --diff-filter=U EMPTY — the "no conflicts to
	# resolve" death branch below — the staged half-port and a deleted state file,
	# a wedge only hand cleanup can undo (verified against real git).
	# Force it off; the pause banner (list_conflicts) flags replayed paths instead.
	if [ "$parents" -gt 1 ]; then
		git -c rerere.autoUpdate=false cherry-pick -m 1 -x --no-commit "$sha" || rc=$?
	else
		git -c rerere.autoUpdate=false cherry-pick -x --no-commit "$sha" || rc=$?
	fi
	if [ "$rc" -ne 0 ]; then
		if git diff --name-only --diff-filter=U | grep -q .; then
			# Lockfiles are mechanically resolvable (run batches only here; `range`
			# has its own call; next/one keep the manual recipe) — resolving them may
			# EMPTY the conflict set, turning this pause into a clean continue.
			if [ "$run_mode" = 1 ]; then
				lockres="$(auto_resolve_lockfiles)"
				if [ -n "$lockres" ]; then
					printf '%s\n' "$lockres" | awk 'NF {print "LOCKAUTO=" $0}' >>"$run_state"
					note "auto-resolved lockfile(s): $(printf '%s' "$lockres" | tr '\n' ' ')"
				fi
			fi
			if git diff --name-only --diff-filter=U | grep -q .; then
				# Remember the conflict set so finalize can journal it (.fork/PORTS.md).
				git -c core.quotepath=false diff --name-only --diff-filter=U | awk '{print "CONFLICT=" $0}' >>"$state"
				write_pause_file conflict "$sha" files \
					"$(git -c core.quotepath=false diff --name-only --diff-filter=U | awk 'NF {s = s (s ? ";" : "") $0} END {printf "%s", s}')"
				if [ "$run_mode" = 1 ]; then
					printf 'PAUSE=%s conflict %s\n' "$(git rev-parse --short "$sha")" \
						"$(git -c core.quotepath=false diff --name-only --diff-filter=U | awk 'NF {s = s (s ? ";" : "") $0} END {printf "%s", s}')" >>"$run_state"
				fi
				printf '\nport.sh: CONFLICT porting %s. Files:\n' "$(git rev-parse --short "$sha")" >&2
				list_conflicts
				[ "$run_mode" = 1 ] && conflict_registry_note
				printf 'Inspect:  ./.fork/conflict-context.sh %s <file>\n' "$sha" >&2
				printf 'Resolve + git add, then: ./.fork/port.sh continue   (or abort)\n' >&2
				[ "$run_mode" = 1 ] && printf '(run batch stays open — after continue, resume with ./.fork/port.sh run)\n' >&2
				exit 1
			fi
			note "all conflicts were lockfiles — auto-resolved; continuing the port"
		else
			rm -f "$state"
			die "cherry-pick failed (rc=$rc) with no conflicts to resolve — see output above"
		fi
	fi
	# Clean apply. In a `run` batch, a pick whose STAGED effect touches registry
	# entries pauses BEFORE committing — the "dangerous clean apply": upstream
	# changed something a customization depends on without a single conflict
	# marker. The operator drift-checks the listed entries, updates
	# .fork/CHANGES.md (+ Test:) if the customization moved, stages, then
	# `continue` finalizes this same port.
	if [ "$run_mode" = 1 ]; then
		rentries="$(registry_entries_for_paths "$(git -c core.quotepath=false diff --cached --name-only)")"
		if [ -n "$rentries" ]; then
			printf 'PAUSE=%s registry %s\n' "$(git rev-parse --short "$sha")" \
				"$(printf '%s\n' "$rentries" | awk 'NF {s = s (s ? ";" : "") $0} END {printf "%s", s}')" >>"$run_state"
			write_pause_file registry "$sha" entries \
				"$(printf '%s\n' "$rentries" | awk 'NF {s = s (s ? ";" : "") $0} END {printf "%s", s}')"
			printf '\nport.sh: PAUSED (registry) porting %s — the pick applied CLEAN, but it touches:\n' "$(git rev-parse --short "$sha")" >&2
			printf '%s\n' "$rentries" | while IFS= read -r e; do
				[ -z "$e" ] && continue
				printf '  - %s\n' "$e" >&2
				entry_origin_commits "$e"
			done
			printf 'The most dangerous port applies cleanly yet changes what a customization depends on.\n' >&2
			printf 'Inspect:  git show %s    ./.fork/brief.sh %s^ %s\n' \
				"$(git rev-parse --short "$sha")" "$(git rev-parse --short "$sha")" "$(git rev-parse --short "$sha")" >&2
			printf 'Drift-check the entries above; update .fork/CHANGES.md (+ Test:) if needed; stage;\n' >&2
			printf 'then: ./.fork/port.sh continue   (or abort). Resume the batch: ./.fork/port.sh run\n' >&2
			exit 1
		fi
	fi
	# Finalize now. If the cherry-pick was EMPTY (upstream change already present in
	# the fork), the tree is unchanged but the pointer file still advances, so
	# finalize commits a pointer-only "already present" port — the backlog shrinks.
	finalize "$sha" "$ref"
}

# Overwrite (or add) one KEY=value line in the run state. awk-to-temp + mv: bash
# 3.2-safe, and the accumulating fact lines (PORT=/EMPTY=/...) pass through.
run_state_set() { # <key> <value>
	local tmp
	tmp="$(mktemp)"
	awk -v k="$1" 'index($0, k "=") != 1' "$run_state" >"$tmp"
	printf '%s=%s\n' "$1" "$2" >>"$tmp"
	mv "$tmp" "$run_state"
}

# BATCH: port the backlog oldest-first with ONE operator decision per PAUSE
# instead of per commit. Clean non-registry picks flow straight through (each
# still its own trailered, individually gated commit — the gate scoped to that
# commit's staged paths); the loop pauses exactly like `next` on a real conflict
# (minus auto-resolved lockfiles) or on a clean pick touching registry entries.
# After a pause: resolve, `./.fork/port.sh continue`, then re-run `run` — the
# batch state persists (INCLUDING --until and the lockfile opt-out) and keeps
# accumulating. When the backlog (or --until / --limit) is done, finish_run
# verifies everything the batch touched (verify.sh --scoped: FULL registry +
# touched entries' Test:), journals ONE fact entry in .fork/PORTS.md, prints a
# timing summary, and clears the state.
cmd_run() {
	local until_arg="" limit=0 refarg="" ref sha until_sha="" t0 t1 ports_t=0 n=0 cli_lockoff=0 backlog_tmp
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--until)
			[ -n "${2:-}" ] || die "usage: ./.fork/port.sh run [--until <ref>] [--limit <N, this invocation only>] [--no-lockfile-auto] [upstream-ref]"
			until_arg="$2"
			shift 2
			;;
		--limit)
			case "${2:-}" in '' | *[!0-9]*) die "--limit needs a positive integer" ;; esac
			limit="$2"
			shift 2
			;;
		--no-lockfile-auto)
			lockauto=0
			cli_lockoff=1
			shift
			;;
		-*) die "unknown flag: $1 (see ./.fork/port.sh --help)" ;;
		*)
			[ -n "$refarg" ] && die "unexpected argument: $1"
			refarg="$1"
			shift
			;;
		esac
	done
	ref="$(resolve_upstream_ref "$refarg")"
	[ -z "$(upstream_pointer)" ] && die "no pointer yet — run ./.fork/port.sh init <sha> [ref] first"
	[ -f "$state" ] && die "a port is in progress — finish it (continue/abort) first"
	[ -f "$unport_state" ] && die "an unport is in progress — finish it (continue/abort) first"
	require_clean_tree
	preflight
	assert_pointer_trailer_consistent
	if [ -n "$until_arg" ]; then
		git rev-parse --verify --quiet "${until_arg}^{commit}" >/dev/null 2>&1 || die "not a commit: $until_arg"
		until_sha="$(git rev-parse "${until_arg}^{commit}")"
	fi
	# Capture the backlog ONCE per invocation (it was re-read per iteration, and
	# start_port re-read it again for the contiguity check — O(N^2) on a long
	# catch-up; and a `| grep -q` validation SIGPIPEs the producer on a long
	# backlog, the exact class the awk-NR==1 note in start_port forbids). Each
	# pause-resume re-enters cmd_run and re-captures, so the snapshot is always
	# current when the loop starts. The EXIT trap covers the pause path (a
	# conflict exits 1 from inside start_port).
	backlog_tmp="$(mktemp)"
	# ${backlog_tmp:-}: the trap outlives this function's locals (it fires at
	# script exit, incl. the pause path), so it must tolerate the var being gone.
	trap 'rm -f "${backlog_tmp:-}"' EXIT
	backlog "$ref" >"$backlog_tmp"
	# Open (or resume) the batch. START/DATE anchor the journal entry; facts
	# (PORT=/EMPTY=/PAUSE=/LOCKAUTO=) accumulate below them across resumes.
	# --until and the lockfile opt-out PERSIST in the batch state so a bare `run`
	# after a pause keeps the invocation's contract (--limit is per-invocation by
	# design: a resume counts from zero). A flag passed on resume overwrites the
	# stored one.
	if [ ! -f "$run_state" ]; then
		if [ -n "$until_sha" ] && ! grep -Fxq "$until_sha" "$backlog_tmp"; then
			die "--until $until_arg is not in the unported backlog of $ref (already ported, or not on its first-parent line?)"
		fi
		printf 'START=%s\nREF=%s\nDATE=%s\n' "$(upstream_pointer)" "$ref" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$run_state"
		[ -n "$until_sha" ] && printf 'UNTIL=%s\n' "$until_sha" >>"$run_state"
		[ "$lockauto" = 0 ] && printf 'LOCKAUTO_OFF=1\n' >>"$run_state"
		: >"$run_touched_file"
	else
		if [ -n "$until_arg" ]; then
			run_state_set UNTIL "$until_sha"
		else
			until_sha="$(awk -F= '/^UNTIL=/{print $2; exit}' "$run_state")"
		fi
		if [ "$cli_lockoff" = 1 ]; then
			run_state_set LOCKAUTO_OFF 1
		elif grep -q '^LOCKAUTO_OFF=1$' "$run_state"; then
			lockauto=0
		fi
		if [ -n "$until_sha" ] && ! grep -Fxq "$until_sha" "$backlog_tmp"; then
			# A resume whose --until was ported by the pause's own `continue`:
			# the batch met its stop condition — finish it instead of overrunning.
			if git merge-base --is-ancestor "$until_sha" "$(upstream_pointer)" 2>/dev/null; then
				finish_run "$ref" 0
				return 0
			fi
			die "--until $(git rev-parse --short "$until_sha") is not in the unported backlog of $ref (not on its first-parent line?)"
		fi
	fi
	run_mode=1
	while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		if [ "$limit" -gt 0 ] && [ "$n" -ge "$limit" ]; then
			note "--limit $limit reached"
			break
		fi
		note "porting $(git rev-parse --short "$sha"): $(git log -1 --format=%s "$sha")"
		t0="$(date +%s)"
		start_port "$sha" "$ref" # a pause exits 1 from inside; the batch state survives it
		t1="$(date +%s)"
		ports_t=$((ports_t + t1 - t0))
		n=$((n + 1))
		if [ -n "$until_sha" ] && [ "$sha" = "$until_sha" ]; then
			note "--until reached ($(git rev-parse --short "$until_sha"))"
			break
		fi
	done <"$backlog_tmp"
	rm -f "$backlog_tmp"
	finish_run "$ref" "$ports_t"
}

# Batch end: verify everything the run touched, journal ONE fact entry, print
# the summary, clear the batch state. Reached only when a run meets its stop
# condition — a pause exits earlier and keeps the state for the resume.
finish_run() { # <ref> <this-invocation-port-seconds>
	local ref="$1" ports_t="$2" start_ptr end_ptr started nport nempty nlock npause paths_tmp vrc=0 vt=0 t0 t1
	if [ ! -f "$run_state" ]; then
		note "nothing to port — up to date with $ref"
		return 0
	fi
	start_ptr="$(awk -F= '/^START=/{print $2; exit}' "$run_state")"
	started="$(awk -F= '/^DATE=/{print $2; exit}' "$run_state")"
	end_ptr="$(upstream_pointer)"
	nport="$(grep -c '^PORT=' "$run_state" || true)"
	nempty="$(grep -c '^EMPTY=' "$run_state" || true)"
	nlock="$(grep -c '^LOCKAUTO=' "$run_state" || true)"
	npause="$(grep -c '^PAUSE=' "$run_state" || true)"
	if [ "$((nport + nempty))" -eq 0 ]; then
		note "run: nothing was ported — clearing batch state"
		rm -f "$run_state" "$run_touched_file" "$scope_tmp_file"
		return 0
	fi
	# Batch-end verification: FULL registry + the Test: of every touched entry.
	# This is what earns the scoped per-commit gates above — nothing is pushed
	# on scoped checks alone. Failure keeps the batch open: fix, commit, re-run.
	paths_tmp="$(mktemp)"
	awk 'NF && !seen[$0]++' "$run_touched_file" >"$paths_tmp" 2>/dev/null || true
	t0="$(date +%s)"
	if [ -x .fork/verify.sh ]; then
		./.fork/verify.sh --scoped --paths "$paths_tmp" || vrc=$?
	fi
	t1="$(date +%s)"
	vt=$((t1 - t0))
	rm -f "$paths_tmp"
	if [ "$vrc" -ne 0 ]; then
		die "batch verify FAILED (exit $vrc) — fix it, commit the fix, then re-run
       ./.fork/port.sh run to finish the batch (its state is kept)"
	fi
	# Journal: the SCRIPT writes the facts; judgment lines (one per pause) are the
	# only thing left for a human/agent to fill. Committed --no-verify like init —
	# a journal write is not an integration.
	{
		printf '\n## run %s %s..%s (%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
			"$(git rev-parse --short "$start_ptr")" "$(git rev-parse --short "$end_ptr")" "$ref"
		printf 'started: %s\n' "$started"
		printf 'ported: %s commits (%s empty, %s lockfile/regen auto-resolves)\n' "$((nport + nempty))" "$nempty" "$nlock"
		grep '^LOCKAUTO=' "$run_state" | sed 's/^LOCKAUTO=/lockfile auto-resolved: /' || true
		grep '^PAUSE=' "$run_state" | sed 's/^PAUSE=/paused: /' || true
		printf 'verify: OK (scoped, %ss)\n' "$vt"
		printf 'timings: ports=%ss verify=%ss\n' "$ports_t" "$vt"
		grep '^PAUSE=' "$run_state" | awk '{sub(/^PAUSE=/, ""); print "Judgment: (fill in) — " $1}' || true
	} >>.fork/PORTS.md
	git add .fork/PORTS.md
	git commit -q --no-verify -m "fork-flow: journal port run ($(git rev-parse --short "$start_ptr")..$(git rev-parse --short "$end_ptr"))"
	note "run complete: $((nport + nempty)) ported ($nempty empty), $npause pause(s), $nlock lockfile auto-resolve(s)"
	note "pointer: $(git rev-parse --short "$start_ptr") -> $(git rev-parse --short "$end_ptr")"
	note "timing: ports=${ports_t}s verify=${vt}s (batch opened $started)"
	rm -f "$run_state" "$run_touched_file" "$scope_tmp_file"
}

# FORECAST: what would `run`/`range` face, without touching the worktree?
# Chained git-merge-tree simulation (git ≥ 2.40 for --write-tree --merge-base;
# PROBED by the first invocation, never version-parsed): each backlog commit is
# three-way merged (base = its first parent) onto a synthetic chain of the
# previous results, so verdicts stay exact until the first conflict. A
# CONFLICTED step chains its conflicted result tree (markers embedded), so
# later verdicts are approximate — flagged in the footer. Registry flags use
# the same anchors as the gate. The synthetic commits touch no refs; gc prunes.
cmd_plan() {
	local rangearg="" refarg="" ref cur ours sha out rc tree files entries verdict subject short csv
	local n=0 nclean=0 nempty=0 nconf=0 nflag=0 mt_ok=1 approx=0 porcelain=0 pv detail ecsv
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--range)
			[ -n "${2:-}" ] || die "usage: ./.fork/port.sh plan [--range <sha|tag>] [--porcelain] [upstream-ref]"
			rangearg="$2"
			shift 2
			;;
		--porcelain)
			porcelain=1
			shift
			;;
		-*) die "unknown flag: $1 (see ./.fork/port.sh --help)" ;;
		*)
			[ -n "$refarg" ] && die "unexpected argument: $1"
			refarg="$1"
			shift
			;;
		esac
	done
	ref="$(resolve_upstream_ref "$refarg")"
	cur="$(upstream_pointer)"
	[ -n "$cur" ] || die "no pointer yet — run ./.fork/port.sh init <sha> [ref] first"
	git rev-parse --verify --quiet "${cur}^{commit}" >/dev/null 2>&1 ||
		die "pointer $cur does not resolve — fix .fork/UPSTREAM first"
	cur="$(git rev-parse "$cur")"
	if [ -n "$rangearg" ]; then
		plan_range "$cur" "$rangearg" "$porcelain"
		return 0
	fi
	ours="$(git rev-parse HEAD)"
	[ "$porcelain" = 0 ] && printf '== plan (%s), oldest first ==\n' "$ref"
	while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		n=$((n + 1))
		short="$(git rev-parse --short "$sha")"
		subject="$(git log -1 --format=%s "$sha")"
		# Registry flag from the upstream commit's own first-parent paths — the
		# same intersection the run-batch pause uses (there: staged paths).
		entries="$(registry_entries_for_paths "$(git -c core.quotepath=false diff-tree -r -m --first-parent --no-commit-id --name-only "$sha")")"
		verdict=""
		pv=""
		files=""
		if [ "$mt_ok" = 1 ]; then
			rc=0
			out="$(git merge-tree --write-tree --no-messages --merge-base="${sha}^1" "$ours" "$sha" 2>/dev/null)" || rc=$?
			if [ "$rc" -gt 1 ] || [ -z "$out" ]; then
				mt_ok=0
				note "git merge-tree --write-tree/--merge-base unavailable (need git ≥ 2.40) — conflict forecast off; registry flags stay exact"
			else
				tree="$(printf '%s\n' "$out" | awk 'NR==1 {print $1}')"
				if [ "$rc" -eq 1 ]; then
					files="$(printf '%s\n' "$out" | awk -F'\t' 'NR>1 && NF>=2 {print $2}' | awk 'NF && !seen[$0]++')"
					csv="$(printf '%s\n' "$files" | awk 'NR<=3 {s=s (s ? "," : "") $0} NR==4 {s=s ",…"} END {printf "%s", s}')"
					verdict="conflict($csv)"
					pv=conflict
					nconf=$((nconf + 1))
					approx=1
				elif [ "$tree" = "$(git rev-parse "${ours}^{tree}")" ]; then
					verdict="empty"
					pv=empty
					nempty=$((nempty + 1))
				else
					verdict="clean"
					pv=clean
					nclean=$((nclean + 1))
				fi
				# Chain: the NEXT step merges onto this result. If commit-tree cannot
				# run (no committer ident), keep the old base — approximate, flagged.
				ours="$(git commit-tree "$tree" -p "$ours" -m 'fork-flow plan simulation' 2>/dev/null)" || {
					ours="$(git rev-parse HEAD)"
					approx=1
				}
			fi
		fi
		if [ "$mt_ok" = 0 ]; then
			verdict="?"
			pv=unknown
		fi
		if [ -n "$entries" ]; then
			nflag=$((nflag + 1))
			csv="$(printf '%s\n' "$entries" | awk 'NR<=3 {s=s (s ? "," : "") $0} NR==4 {s=s ",…"} END {printf "%s", s}')"
			verdict="${verdict:+$verdict+}flag($csv)"
		fi
		if [ "$porcelain" = 1 ]; then
			# One TAB-separated record per commit: <full-sha> <verdict[+flag]>
			# <detail: ;-joined FULL conflict files and/or entries> <subject>.
			# No 3-item truncation here — the csv capping is prose-only.
			detail=""
			if [ -n "$files" ]; then
				detail="$(printf '%s\n' "$files" | awk 'NF {s = s (s ? ";" : "") $0} END {printf "%s", s}')"
			fi
			if [ -n "$entries" ]; then
				ecsv="$(printf '%s\n' "$entries" | awk 'NF {s = s (s ? ";" : "") $0} END {printf "%s", s}')"
				detail="${detail:+$detail;}$ecsv"
			fi
			printf '%s\t%s%s\t%s\t%s\n' "$sha" "${pv:-clean}" "$([ -n "$entries" ] && printf '+flag')" "$detail" "$subject"
		else
			printf '  %s  %s  %s\n' "$short" "${verdict:-clean}" "$subject"
		fi
	done <<EOF
$(backlog "$ref")
EOF
	if [ "$porcelain" = 1 ]; then
		# Exit stays 0 (existing consumers): the summary line carries the signal.
		printf '#summary\ttotal=%d\tclean=%d\tempty=%d\tconflict=%d\tflagged=%d\tpauses=%d\tapprox=%d\tforecast=%d\n' \
			"$n" "$nclean" "$nempty" "$nconf" "$nflag" "$((nconf + nflag))" "$approx" "$mt_ok"
		return 0
	fi
	if [ "$n" -eq 0 ]; then
		printf '  (up to date)\n'
		return 0
	fi
	printf -- '-- %d commits: %d clean, %d empty, %d conflict, %d registry-flagged' "$n" "$nclean" "$nempty" "$nconf" "$nflag"
	[ "$mt_ok" = 0 ] && printf ' (conflict forecast unavailable)'
	printf -- '\n'
	[ "$approx" = 1 ] && printf '   (verdicts after the first conflict are approximate — the simulation chains a conflicted tree)\n'
	printf '   run them: ./.fork/port.sh run    pauses expected: %d\n' "$((nconf + nflag))"
	return 0
}

# One squash forecast of pointer..<sha> — what `range` will face. merge-tree is
# an EXACT model of range's apply (same base, same merge machinery as the
# synthetic-commit cherry-pick range performs).
plan_range() { # <cur-pointer> <range-arg> [porcelain]
	local cur="$1" rangearg="$2" porcelain="${3:-0}" rsha out rc span_paths rents fconf mt_avail=1 f e
	git rev-parse --verify --quiet "${rangearg}^{commit}" >/dev/null 2>&1 || die "not a commit: $rangearg"
	rsha="$(git rev-parse "${rangearg}^{commit}")"
	[ "$rsha" = "$cur" ] && die "$rangearg is already the pointer — nothing to port"
	git merge-base --is-ancestor "$cur" "$rsha" 2>/dev/null ||
		die "pointer $(git rev-parse --short "$cur") is not an ancestor of $rangearg — wrong line?"
	span_paths="$(git -c core.quotepath=false diff --name-only "$cur" "$rsha")"
	rents="$(registry_entries_for_paths "$span_paths")"
	rc=0
	out="$(git merge-tree --write-tree --no-messages --merge-base="$cur" HEAD "$rsha" 2>/dev/null)" || rc=$?
	fconf=""
	if [ "$rc" -gt 1 ] || [ -z "$out" ]; then
		mt_avail=0
	elif [ "$rc" -eq 1 ]; then
		fconf="$(printf '%s\n' "$out" | awk -F'\t' 'NR>1 && NF>=2 {print $2}' | awk 'NF && !seen[$0]++')"
	fi
	if [ "$porcelain" = 1 ]; then
		# One `conflict\t<file>` line per forecast file, one `flag\t<entry>` per
		# span entry, then the #summary record. Exit stays 0.
		printf '%s\n' "$fconf" | while IFS= read -r f; do
			[ -n "$f" ] && printf 'conflict\t%s\n' "$f"
		done
		printf '%s\n' "$rents" | while IFS= read -r e; do
			[ -n "$e" ] && printf 'flag\t%s\n' "$e"
		done
		printf '#summary\tcommits=%s\tfiles=%s\tconflicts=%s\tflagged=%s\tforecast=%s\n' \
			"$(git rev-list --first-parent --count "$cur..$rsha")" \
			"$(printf '%s\n' "$span_paths" | grep -c . || true)" \
			"$(printf '%s\n' "$fconf" | grep -c . || true)" \
			"$(printf '%s\n' "$rents" | grep -c . || true)" \
			"$mt_avail"
		return 0
	fi
	printf '== plan --range %s..%s ==\n' "$(git rev-parse --short "$cur")" "$(git rev-parse --short "$rsha")"
	printf 'span: %s upstream first-parent commits, %s files changed\n' \
		"$(git rev-list --first-parent --count "$cur..$rsha")" "$(printf '%s\n' "$span_paths" | grep -c . || true)"
	if [ "$mt_avail" = 0 ]; then
		note "git merge-tree unavailable (need git ≥ 2.40) — no conflict forecast; range will discover them"
	elif [ -n "$fconf" ]; then
		printf 'forecast conflicts:\n'
		printf '%s\n' "$fconf" | sed 's/^/  - /'
	else
		printf 'forecast: applies clean\n'
	fi
	if [ -n "$rents" ]; then
		printf 'registry entries in span (drift-check during the port):\n'
		printf '%s\n' "$rents" | sed 's/^/  - /'
	fi
	printf 'next: git fetch --tags upstream && ./.fork/port.sh range %s\n' "$rangearg"
	return 0
}

# Stage the (already rewound) pointer and make the gated unport commit. Shared by a
# clean revert and by `continue` after a manual resolve. `git revert --no-commit` of the
# port commit ALREADY rewound + staged .fork/UPSTREAM (the port advanced it in that same
# commit), so unlike finalize() we do NOT write_pointer — we only record the Unport
# trailer so audit/commit-msg recognize the backward pointer move as legitimate.
finalize_unport() { # <un-ported-full-sha> <expected-previous-pointer>
	local sha="$1" expected="$2" expected_ref="$3" actual actual_ref staged staged_ref msg conflicts="" staged_tree
	if git ls-files --unmerged --error-unmatch -- . >/dev/null 2>&1; then
		list_conflicts
		die "unresolved conflicts remain (above) — resolve + 'git add', then ./.fork/port.sh continue"
	fi
	actual="$(upstream_pointer)"
	actual_ref="$(upstream_pointer_ref)"
	[ "$actual" = "$expected" ] && [ "$actual_ref" = "$expected_ref" ] || die "unport did not rewind .fork/UPSTREAM to $expected ${expected_ref:-<no-ref>} (found ${actual:-unset} ${actual_ref:-<no-ref>})
       restore the revert's pointer change, stage it, then run ./.fork/port.sh continue"
	git add "$changes_file"
	staged="$(git show ":$changes_file" 2>/dev/null | awk 'NF && $1 !~ /^#/ {print $1; exit}')"
	staged_ref="$(git show ":$changes_file" 2>/dev/null | awk 'NF && $1 !~ /^#/ {print $2; exit}')"
	[ "$staged" = "$expected" ] && [ "$staged_ref" = "$expected_ref" ] || die "staged .fork/UPSTREAM is $staged ${staged_ref:-<no-ref>}, expected $expected ${expected_ref:-<no-ref>}"
	msg="$(printf 'fork-flow: revert port of %s\n\nUndoes the port of upstream commit %s, rewinding .fork/UPSTREAM to the\nprevious pointer. Re-port it later with ./.fork/port.sh next.\n\n%s: %s\n' \
		"$(git rev-parse --short "$sha")" "$sha" "$UNPORT_TRAILER" "$sha")"
	# Journal a CONFLICTED unport like a conflicted port (see finalize) — the redo
	# decisions are exactly what a later re-port needs on record.
	if [ -f "$unport_state" ] && ! grep -q '^JOURNALED=1$' "$unport_state"; then
		conflicts="$(awk '/^CONFLICT=/{print substr($0,10)}' "$unport_state")"
		if [ -n "$conflicts" ]; then
			{
				printf '\n## %s — un-ported %s (port.sh revert)\n' "$(date +%Y-%m-%d)" "$(git rev-parse --short "$sha")"
				printf 'Conflicts:\n'
				printf '%s\n' "$conflicts" | while IFS= read -r c; do
					[ -n "$c" ] && printf '  - %s — resolution: (fill in)\n' "$c"
				done
				printf 'Decisions: (fill in — registry entries retargeted/restored by this revert)\n'
			} >>.fork/PORTS.md
			git add .fork/PORTS.md
			printf 'JOURNALED=1\n' >>"$unport_state"
		fi
	fi
	# The pre-commit integration gate runs verify.sh --registry here (pointer is staged):
	# undoing a port must not silently break a customization either.
	inline_gate unport
	# FORK_FLOW_PORT=1 + rewrite detection: same contract as finalize().
	staged_tree="$(git write-tree)"
	printf '%s' "$msg" | FORK_FLOW_PORT=1 git commit -F -
	rm -f "$unport_state" "$pause_file"
	warn_if_hook_rewrote "$staged_tree"
	note "reverted port of $sha; pointer now $(upstream_pointer || echo '(unset)')"
}

# Un-port the NEWEST port: `git revert` the fork commit that advanced the pointer to its
# current value (which rewinds .fork/UPSTREAM automatically), then commit it gated with a
# Fork-Flow-Unport trailer. Reverts go newest-first — the mirror of port-oldest-first
# contiguity — so an explicit SHA must name the current pointer.
cmd_revert() { # [<upstream-sha>]
	local want="${1:-}" cur target tr sha prev prev_ref rc
	[ -f "$state" ] && die "a port is in progress — finish it (continue/abort) first"
	[ -f "$unport_state" ] && die "an unport is already in progress — continue/abort it first"
	require_clean_tree
	preflight
	cur="$(upstream_pointer)"
	[ -z "$cur" ] && die "no pointer set — nothing to revert"
	git rev-parse --verify --quiet "${cur}^{commit}" >/dev/null 2>&1 ||
		die "pointer $cur does not resolve — fix .fork/UPSTREAM before reverting"
	cur="$(git rev-parse "$cur")"
	# An explicit SHA is a safety assertion: you may only revert the NEWEST port, i.e. the
	# one the pointer names. Reverting an older port out of order would leave the pointer
	# ahead of the tree (audit's consistency check would then flag it).
	if [ -n "$want" ]; then
		git rev-parse --verify --quiet "${want}^{commit}" >/dev/null 2>&1 || die "not a commit: $want"
		want="$(git rev-parse "$want")"
		[ "$want" = "$cur" ] || die "can only revert the NEWEST port: the pointer is $(git rev-parse --short "$cur"), not $(git rev-parse --short "$want")
       (revert in reverse port order — newest first)"
	fi
	# Find the fork commit whose port trailer names the current pointer — the in-effect
	# newest port. Matching the TRAILER to the pointer (not merely "the newest port
	# commit") means a re-port wins over its reverted original, and a corrupt pointer that
	# names no reachable port is refused rather than reverting the wrong commit.
	target=""
	while IFS= read -r sha; do
		[ -z "$sha" ] && continue
		tr="$(port_trailer_sha "$sha")"
		[ -z "$tr" ] && continue
		if [ "$(git rev-parse "$tr" 2>/dev/null)" = "$cur" ]; then
			target="$sha"
			break
		fi
	done < <(git log --format='%H' HEAD 2>/dev/null || true)
	[ -z "$target" ] &&
		die "no reachable commit ports $(git rev-parse --short "$cur") — .fork/UPSTREAM may be hand-edited (expected a $PORT_TRAILER trailer)"
	# The pointer being the INIT pointer means nothing has been ported — there is no port
	# to revert (reverting init would just un-initialize the fork).
	if git log -1 --format='%B' "$target" 2>/dev/null | grep -q "^$INIT_TRAILER:"; then
		die "pointer is at the init commit (nothing ported) — port forward first, or undo init by hand"
	fi
	prev="$(git show "$target^:$changes_file" 2>/dev/null | awk 'NF && $1 !~ /^#/ {print $1; exit}')"
	prev_ref="$(git show "$target^:$changes_file" 2>/dev/null | awk 'NF && $1 !~ /^#/ {print $2; exit}')"
	[ -n "$prev" ] || die "port commit $(git rev-parse --short "$target") has no previous pointer to restore"
	note "reverting port $(git rev-parse --short "$target") (un-ports $(git rev-parse --short "$cur"))"
	# Record state BEFORE touching the tree so abort/continue always have it.
	printf 'UNPORT=%s\nPREV=%s\nPREV_REF=%s\n' "$cur" "$prev" "$prev_ref" >"$unport_state"
	rc=0
	# autoUpdate forced off for the same reasons as start_port's cherry-pick.
	git -c rerere.autoUpdate=false revert --no-commit "$target" || rc=$?
	if [ "$rc" -ne 0 ]; then
		if git diff --name-only --diff-filter=U | grep -q .; then
			# Remember the conflict set so finalize_unport can journal it (.fork/PORTS.md).
			git -c core.quotepath=false diff --name-only --diff-filter=U | awk '{print "CONFLICT=" $0}' >>"$unport_state"
			printf '\nport.sh: CONFLICT reverting %s. Files:\n' "$(git rev-parse --short "$target")" >&2
			list_conflicts
			printf 'Resolve + git add, then: ./.fork/port.sh continue   (or abort)\n' >&2
			exit 1
		fi
		git revert --abort >/dev/null 2>&1 || git reset -q --hard HEAD
		rm -f "$unport_state"
		die "revert failed (rc=$rc) with no conflicts to resolve — see output above"
	fi
	# Clean revert: .fork/UPSTREAM is already rewound + staged; finalize now (gated).
	finalize_unport "$cur" "$prev" "$prev_ref"
}

cmd_one() {
	local sha="${1:-}" ref
	[ -n "$sha" ] || die "usage: ./.fork/port.sh one <sha> [upstream-ref]"
	ref="$(resolve_upstream_ref "${2:-}")"
	git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1 || die "not a commit: $sha"
	sha="$(git rev-parse "$sha")"
	start_port "$sha" "$ref"
}

cmd_next() {
	local ref sha
	ref="$(resolve_upstream_ref "${1:-}")"
	[ -z "$(upstream_pointer)" ] && die "no pointer yet — run ./.fork/port.sh init <sha> [ref] first"
	# awk NR==1 (drains stdin), never `head -1` — see the SIGPIPE note in start_port.
	sha="$(backlog "$ref" | awk 'NR==1')"
	[ -z "$sha" ] && {
		note "nothing to port — up to date with $ref"
		return 0
	}
	note "porting $(git rev-parse --short "$sha"): $(git log -1 --format=%s "$sha")"
	start_port "$sha" "$ref"
}

# EARLY out-of-order port (the security fast path): cherry-pick ONE unported
# upstream commit NOW without advancing the pointer — contiguity is preserved
# because the pointer doesn't move; the commit carries a Fork-Flow-Early trailer
# (exact-SHA dedupe at catch-up, no patch-id guessing). The picked files count as
# unregistered fork changes in audit until registered — that pressure is the
# point: register immediately (fork-change skill), and retire the entry when the
# catch-up port lands empty.
cmd_pick() { # <sha> [upstream-ref]
	local sha="${1:-}" ref parents rc=0 head_sha blist ptr_disp
	[ -n "$sha" ] || die "usage: ./.fork/port.sh pick <upstream-sha> [upstream-ref]"
	[ -f "$state" ] && die "a port is already in progress — continue/abort it first"
	[ -f "$unport_state" ] && die "an unport is in progress — finish it (continue/abort) first"
	require_clean_tree
	preflight
	assert_pointer_trailer_consistent
	ref="$(resolve_upstream_ref "${2:-}")"
	git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1 || die "not a commit: $sha"
	sha="$(git rev-parse "${sha}^{commit}")"
	blist="$(backlog "$ref")"
	# awk drains stdin (the drain-the-pipe rule — see start_port's SIGPIPE note);
	# a grep -q here would close the pipe early on a long backlog.
	printf '%s\n' "$blist" | awk -v s="$sha" '$0==s{f=1} END{exit f?0:1}' ||
		die "$sha is not in the unported backlog of $ref — already ported, or not on its first-parent line"
	head_sha="$(printf '%s\n' "$blist" | awk 'NR==1')"
	[ "$sha" = "$head_sha" ] &&
		die "that is the NEXT unported commit — port it normally: ./.fork/port.sh next"
	ptr_disp="$(upstream_pointer)"
	if [ -n "$ptr_disp" ]; then ptr_disp="$(git rev-parse --short "$ptr_disp")"; else ptr_disp="(unset)"; fi
	note "picking $(git rev-parse --short "$sha") EARLY (pointer stays at $ptr_disp)"
	# Record state BEFORE touching the tree so abort/continue always have it;
	# EARLY=1 routes `continue` to finalize_early instead of finalize.
	printf 'SHA=%s\nREF=%s\nEARLY=1\n' "$sha" "$ref" >"$state"
	# Same pick mechanics as start_port: a merge replays its first-parent diff
	# (-m 1); -x + --no-commit; rerere.autoUpdate forced off so a remembered
	# resolution stays unmerged for review.
	parents="$(git rev-list --parents -n1 "$sha" | awk '{print NF-1}')"
	if [ "$parents" -gt 1 ]; then
		git -c rerere.autoUpdate=false cherry-pick -m 1 -x --no-commit "$sha" || rc=$?
	else
		git -c rerere.autoUpdate=false cherry-pick -x --no-commit "$sha" || rc=$?
	fi
	if [ "$rc" -ne 0 ]; then
		if git diff --name-only --diff-filter=U | grep -q .; then
			git -c core.quotepath=false diff --name-only --diff-filter=U | awk '{print "CONFLICT=" $0}' >>"$state"
			write_pause_file conflict "$sha" files \
				"$(git -c core.quotepath=false diff --name-only --diff-filter=U | awk 'NF {s = s (s ? ";" : "") $0} END {printf "%s", s}')"
			printf '\nport.sh: CONFLICT picking %s EARLY. Files:\n' "$(git rev-parse --short "$sha")" >&2
			list_conflicts
			printf 'Inspect:  ./.fork/conflict-context.sh %s <file>\n' "$sha" >&2
			printf 'Resolve + git add, then: ./.fork/port.sh continue   (or abort)\n' >&2
			exit 1
		fi
		git reset -q --hard HEAD
		rm -f "$state"
		die "cherry-pick failed (rc=$rc) with no conflicts to resolve — see output above"
	fi
	finalize_early "$sha"
}

# SHA-BOUND fast-forward landing for the PR-branch flow (port on port/<date>,
# push, PR to the base branch, land after CI): the SHA whose checks passed IS
# the SHA that becomes the base branch, enforced by a NON-FORCE SHA-addressed
# push — a non-ff race REJECTS, which is the concurrency guard. Requires gh
# (checks binding reads the PR's statusCheckRollup via gh's bundled --jq — no
# new dependency); forks off GitHub simply don't use this subcommand. gh JSON
# field names verified against gh 2.89.
cmd_land() { # [--dry-run] [--no-checks] [<pr-number>]
	local dry=0 nochecks=0 pr="" line prnum prstate tested headref baseref rollup bad
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--dry-run)
			dry=1
			shift
			;;
		--no-checks)
			nochecks=1
			shift
			;;
		-*) die "usage: ./.fork/port.sh land [--dry-run] [--no-checks] [<pr-number>]" ;;
		*)
			[ -n "$pr" ] && die "unexpected argument: $1"
			pr="$1"
			shift
			;;
		esac
	done
	have_cmd gh || die "land needs the GitHub CLI (gh) on PATH — https://cli.github.com (brew install gh)"
	require_clean_tree
	# Resolve the PR: explicit number, else the current branch's PR. ONE gh call
	# returns metadata AND the check rollup so the checks are bound to the SAME
	# headRefOid snapshot we push — two calls would race a PR head moving between
	# them (checks from the new head, push of the old SHA).
	line="$(gh pr view ${pr:+"$pr"} --json number,state,headRefOid,headRefName,baseRefName,statusCheckRollup \
		--jq '([.number, .state, .headRefOid, .headRefName, .baseRefName] | @tsv), (.statusCheckRollup[] | [(.name // .context // "check"), (.conclusion // .state // "PENDING")] | @tsv)' 2>/dev/null)" ||
		die "no PR found${pr:+ for #$pr} on the current branch — open one (gh pr create --base <base>) or pass the number"
	IFS=$'\t' read -r prnum prstate tested headref baseref <<EOF
$line
EOF
	rollup="$(printf '%s\n' "$line" | awk 'NR>1 && NF')"
	[ -n "$tested" ] || die "gh returned no head SHA for PR #${prnum:-?} — gh too old? (needs --json headRefOid)"
	[ "$prstate" = "OPEN" ] || die "PR #$prnum is $prstate — only an OPEN PR can land"
	# Checks binding: every rollup node must be SUCCESS/NEUTRAL/SKIPPED. A node is
	# a CheckRun (name+conclusion; conclusion empty while running) or a legacy
	# StatusContext (context+state) — normalized in the --jq above. Empty rollup
	# is a refusal: landing unchecked defeats the point (--no-checks overrides
	# deliberately).
	if [ "$nochecks" = 0 ]; then
		[ -n "$rollup" ] || die "no checks found on the PR head — is the fork-flow CI gate enabled? (--no-checks overrides)"
		bad="$(printf '%s\n' "$rollup" | awk -F'\t' 'NF && toupper($2)!="SUCCESS" && toupper($2)!="NEUTRAL" && toupper($2)!="SKIPPED"')"
		[ -z "$bad" ] || die "PR #$prnum has non-passing checks:
$(printf '%s\n' "$bad" | sed 's/^/         /')
       wait for CI (gh pr checks $prnum --watch) or override with --no-checks"
	fi
	# Local binding: the tested SHA must exist locally, and a local head branch
	# that moved past it means changes CI never saw — push and let checks re-run.
	git fetch -q origin || die "git fetch origin failed — cannot verify the tested SHA locally"
	git rev-parse --verify --quiet "${tested}^{commit}" >/dev/null 2>&1 ||
		die "tested SHA $tested is not in the local object store even after fetching origin"
	if git rev-parse --verify --quiet "refs/heads/$headref" >/dev/null 2>&1 &&
		[ "$(git rev-parse "refs/heads/$headref")" != "$tested" ]; then
		die "local branch $headref drifted after CI: local $(git rev-parse --short "refs/heads/$headref") != tested $(git rev-parse --short "$tested")
       — push the branch and let the checks re-run before landing"
	fi
	if [ "$dry" = 1 ]; then
		printf 'land --dry-run (PR #%s, nothing pushed):\n' "$prnum"
		if [ "$nochecks" = 0 ]; then
			printf 'checks:\n'
			printf '%s\n' "$rollup" | awk -F'\t' 'NF {printf "  %s: %s\n", $1, $2}'
		else
			printf 'checks: SKIPPED (--no-checks)\n'
		fi
		printf 'would push:\n  git push origin %s:refs/heads/%s\n' "$tested" "$baseref"
		return 0
	fi
	git push origin "${tested}:refs/heads/${baseref}"
	# Bring the local base branch along when it exists (best-effort convenience).
	if git rev-parse --verify --quiet "refs/heads/$baseref" >/dev/null 2>&1; then
		git switch "$baseref" 2>/dev/null && git pull --ff-only || true
	fi
	note "landed $(git rev-parse --short "$tested") on $baseref (SHA-bound, no force)"
}

# CATCH-UP: squash-port the WHOLE span pointer..<sha> as ONE gated commit. The
# per-commit loop stays the default for small backlogs (individually understood,
# individually revertible ports); range is the catch-up unit for a fork that fell
# releases behind, where a hot file would otherwise re-conflict on every upstream
# touch of it. The span is applied as a CHERRY-PICK of one synthetic commit (the
# span's end tree parented on the pointer), so it runs the SAME merge machinery
# as per-commit ports: rename detection, merge=ours + mergiraf drivers (ll_merge),
# zdiff3 markers, native modify/delete + add/add conflicts, and automatic rerere
# record/replay. One conflict set per file. Use it tag-by-tag (oldest release
# first), then return to `next`. Invariants kept: forward-only (assert_forward),
# contiguous by construction (the span STARTS at the pointer), pointer staged in
# the same commit (the gate fires), and `revert` undoes it like any port (the
# pointer rewinds to <from> automatically).
cmd_range() { # [--no-lockfile-auto] <sha|tag> [upstream-ref]
	local sha ref cur rc n synth lockres=""
	while [ "${1:-}" = "--no-lockfile-auto" ]; do
		lockauto=0
		shift
	done
	sha="${1:-}"
	[ -n "$sha" ] || die "usage: ./.fork/port.sh range [--no-lockfile-auto] <upstream-sha|tag> [upstream-ref]"
	[ -f "$state" ] && die "a port is already in progress — continue/abort it first"
	[ -f "$unport_state" ] && die "an unport is in progress — finish it (continue/abort) first"
	ref="$(resolve_upstream_ref "${2:-}")"
	git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null 2>&1 || die "not a commit: $sha"
	sha="$(git rev-parse "${sha}^{commit}")"
	cur="$(upstream_pointer)"
	[ -n "$cur" ] || die "no pointer yet — run ./.fork/port.sh init <sha> [ref] first"
	git rev-parse --verify --quiet "${cur}^{commit}" >/dev/null 2>&1 ||
		die "pointer $cur does not resolve — fix .fork/UPSTREAM first"
	cur="$(git rev-parse "$cur")"
	[ "$sha" = "$cur" ] && die "$sha is already the pointer — nothing to port"
	require_clean_tree
	preflight
	assert_pointer_trailer_consistent
	assert_forward "$sha"
	# The span's END must sit on the line you port from, or the next backlog would lie.
	git merge-base --is-ancestor "$sha" "$ref" 2>/dev/null ||
		die "$sha is not an ancestor of $ref — pass the ref this tag/sha belongs to"
	n="$(git rev-list --first-parent --count "$cur..$sha")"
	note "squash-porting $n upstream commits: $(git rev-parse --short "$cur")..$(git rev-parse --short "$sha")"
	# Record state BEFORE touching the tree so abort/continue always have it.
	printf 'SHA=%s\nREF=%s\nFROM=%s\n' "$sha" "$ref" "$cur" >"$state"
	if git diff --quiet "$cur" "$sha"; then
		finalize "$sha" "$ref" "$cur" # span is a no-op (already present): pointer-only port
		return 0
	fi
	rc=0
	# ONE synthetic commit holding the span's end tree, parented on the pointer,
	# then cherry-picked onto HEAD — git's real merge machinery does the rest.
	# Fixed idents so a machine with no user.* config still works (cmd_plan
	# degrades on a missing ident; range must not). No -x: finalize writes the
	# real message with the Fork-Flow-Port + Fork-Flow-Port-From trailers.
	synth="$(GIT_AUTHOR_NAME=fork-flow GIT_AUTHOR_EMAIL=fork-flow@invalid \
		GIT_COMMITTER_NAME=fork-flow GIT_COMMITTER_EMAIL=fork-flow@invalid \
		git commit-tree "${sha}^{tree}" -p "$cur" -m "fork-flow range synthesis ${cur}..${sha}")" ||
		{
			rm -f "$state"
			die "cannot synthesize the span commit (git commit-tree failed) — object store incomplete? git fetch upstream and retry"
		}
	# rerere.autoUpdate (user/global config) would silently STAGE any remembered
	# resolution — same trap as start_port's cherry-pick. Force it off; the pause
	# banner (list_conflicts) flags replayed paths instead. No explicit `git
	# rerere` call: the cherry-pick machinery records/replays on its own.
	git -c rerere.autoUpdate=false cherry-pick --no-commit "$synth" || rc=$?
	if git diff --name-only --diff-filter=U | grep -q .; then
		# Lockfiles (+ .fork/REGEN rules) first: mechanically resolvable — on a
		# months-long span the lockfile conflicts every time; resolving them
		# here may even empty the whole conflict set.
		lockres="$(auto_resolve_lockfiles)"
		if [ -n "$lockres" ]; then
			printf '%s\n' "$lockres" | awk 'NF {print "LOCKAUTO=" $0}' >>"$state"
			note "auto-resolved lockfile(s): $(printf '%s' "$lockres" | tr '\n' ' ')"
		fi
		if ! git diff --name-only --diff-filter=U | grep -q .; then
			finalize "$sha" "$ref" "$cur"
			return 0
		fi
		# Remember the conflict set so finalize can journal it (.fork/PORTS.md).
		git -c core.quotepath=false diff --name-only --diff-filter=U | awk '{print "CONFLICT=" $0}' >>"$state"
		write_pause_file conflict "$sha" files \
			"$(git -c core.quotepath=false diff --name-only --diff-filter=U | awk 'NF {s = s (s ? ";" : "") $0} END {printf "%s", s}')"
		printf '\nport.sh: CONFLICTS in range %s..%s. Files:\n' "$(git rev-parse --short "$cur")" "$(git rev-parse --short "$sha")" >&2
		list_conflicts
		conflict_registry_note
		printf 'Inspect:  ./.fork/conflict-context.sh %s..%s <file>\n' "$cur" "$sha" >&2
		printf 'Resolve + git add, then: ./.fork/port.sh continue   (or abort)\n' >&2
		exit 1
	fi
	if [ "$rc" -ne 0 ]; then
		git reset -q --hard HEAD
		rm -f "$state"
		die "range cherry-pick failed (rc=$rc) with no conflicts to resolve — see output above.
       Usually a blob missing locally: git fetch upstream, then retry; if it persists,
       port per-commit: ./.fork/port.sh next"
	fi
	finalize "$sha" "$ref" "$cur"
}

cmd_continue() {
	# An unport (revert) in progress takes precedence — `git revert` already rewound the
	# pointer, so we only need to finalize the gated commit.
	if [ -f "$unport_state" ]; then
		local usha prev prev_ref
		usha="$(awk -F= '/^UNPORT=/{print $2}' "$unport_state")"
		prev="$(awk -F= '/^PREV=/{print $2}' "$unport_state")"
		prev_ref="$(awk -F= '/^PREV_REF=/{print $2}' "$unport_state")"
		[ -n "$usha" ] || die "unport state file is corrupt (no SHA) — ./.fork/port.sh abort and retry"
		[ -n "$prev" ] || die "unport state file is corrupt (no previous pointer) — ./.fork/port.sh abort and retry"
		finalize_unport "$usha" "$prev" "$prev_ref"
		return
	fi
	[ -f "$state" ] || die "no port in progress"
	local sha ref from was_run=0
	if grep -q '^RUN=1$' "$state" 2>/dev/null; then was_run=1; fi
	sha="$(awk -F= '/^SHA=/{print $2}' "$state")"
	ref="$(awk -F= '/^REF=/{print $2}' "$state")"
	from="$(awk -F= '/^FROM=/{print $2}' "$state")"
	[ -n "$sha" ] || die "state file is corrupt (no SHA) — ./.fork/port.sh abort and retry"
	# An EARLY pick finalizes without touching the pointer — branch BEFORE the
	# port finalize so its corrupt-state checks never see an early state.
	if grep -q '^EARLY=1$' "$state" 2>/dev/null; then
		finalize_early "$sha"
		return
	fi
	finalize "$sha" "$ref" "$from"
	if [ "$was_run" = 1 ]; then
		note "run batch still open — resume/finish it: ./.fork/port.sh run"
	fi
}

cmd_abort() {
	# An unport uses `git revert`, which DOES leave a sequencer/REVERT_HEAD (unlike a
	# --no-commit cherry-pick), so `git revert --abort` is the clean undo here.
	if [ -f "$unport_state" ]; then
		git revert --abort >/dev/null 2>&1 || git reset -q --hard HEAD
		git reset -q --merge >/dev/null 2>&1 || true
		rm -f "$unport_state" "$pause_file"
		note "unport aborted; tree restored to HEAD"
		return
	fi
	[ -f "$state" ] || die "no port in progress"
	# `cherry-pick --no-commit` leaves no sequencer, so --abort won't work; hard-reset
	# the worktree/index back to HEAD and drop the state.
	git reset -q --hard HEAD
	git reset -q --merge >/dev/null 2>&1 || true
	rm -f "$state" "$pause_file"
	note "port aborted; tree restored to HEAD"
	if [ -f "$run_state" ]; then
		note "the run batch stays open — resume with ./.fork/port.sh run, or forget it: rm $run_state"
	fi
}

case "${1:-}" in
init)
	shift
	cmd_init "$@"
	;;
list)
	shift
	cmd_list "$@"
	;;
plan)
	shift
	cmd_plan "$@"
	;;
run)
	shift
	cmd_run "$@"
	;;
next)
	shift
	cmd_next "$@"
	;;
one)
	shift
	cmd_one "$@"
	;;
pick)
	shift
	cmd_pick "$@"
	;;
land)
	shift
	cmd_land "$@"
	;;
range)
	shift
	cmd_range "$@"
	;;
revert)
	shift
	cmd_revert "$@"
	;;
continue) cmd_continue ;;
abort) cmd_abort ;;
status)
	shift
	cmd_status "$@"
	;;
"" | -h | --help)
	sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
	;;
*) die "unknown subcommand: $1 (try ./.fork/port.sh --help)" ;;
esac
