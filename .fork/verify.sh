#!/usr/bin/env bash
# .fork/verify.sh — the one real gate that proves the fork still works.
#
#   ./.fork/verify.sh --fast                  quick feedback while resolving (typecheck-only)
#   ./.fork/verify.sh --registry [--scope f]  only the per-customization Verifies + the
#                                             merge=ours backstop (no build/install), so you
#                                             can confirm your customizations survived even
#                                             while the merged build is still red. --scope
#                                             (or $FORK_FLOW_GATE_SCOPE, exported by port.sh
#                                             around each batch commit) narrows the run to
#                                             entries whose anchors match the newline-
#                                             delimited repo-relative paths in f — the cheap
#                                             per-commit gate of a `port.sh run` batch; the
#                                             batch end still verifies the FULL set (--scoped).
#   ./.fork/verify.sh --scoped [--paths f]    FULL registry + the Test: of every entry whose
#                                             anchors match a path in f (every Test: when
#                                             --paths is absent). No install/build — the fast
#                                             local behavior check after a port run on a
#                                             worked-in tree; CI's full gate is the
#                                             from-scratch backstop.
#   ./.fork/verify.sh --prove <slug>          mechanized watched-failure proof of a COMMITTED
#                                             entry: reverts its Touches to the porting base,
#                                             requires the Verify to FAIL there and PASS again
#                                             restored (a Verify that passes with the
#                                             customization removed protects nothing)
#   ./.fork/verify.sh                         full gate before committing a merge
#
# The Fork Maintenance notes (AGENTS.md) sketch a pnpm example; this generalizes it so
# the gate is correct whether the fork is Node (incl. Next.js/Vue/React),
# Rust, Python, PHP/Laravel, Ruby/Rails, Swift, or not yet wired to a stack.
# Two things always hold:
#   1. the merge=ours backstop (full runs) fails if .gitattributes names a
#      merge=ours path that no longer exists;
#   2. a full run proves the fork builds and its tests pass.
# Adjust the per-stack commands for your project as it grows.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Shared helpers (merge_ours_paths, …) — one copy for all scripts, see .fork/lib.sh.
# shellcheck source=/dev/null
. .fork/lib.sh

# The shared brain self-checks before anything else: a silently broken lib.sh helper
# would turn the checks below into no-ops that still print OK (anchors stop matching,
# trailers stop parsing — fail-quiet, the kit's worst failure mode). ~1ms, no git.
lib_selftest || {
	echo 'verify.sh: .fork/lib.sh self-test FAILED (above) — fix lib.sh before trusting any gate result' >&2
	exit 1
}

# modes: full (default) | fast (typecheck-only) | registry (Verifies + backstop only,
#        optionally scoped to a path set) | scoped (full registry + targeted Test:
#        commands of touched entries) | prove (mechanized watched-failure proof of
#        one committed entry's Verify)
mode=full
scope_file=""
paths_file=""
prove_slug=""
usage() {
	echo "usage: ./.fork/verify.sh [--fast | --registry [--scope <file>] | --scoped [--paths <file>] | --prove <slug>]" >&2
	exit 2
}
if [ "$#" -gt 0 ]; then
	case "$1" in
	--fast) mode=fast ;;
	--registry) mode=registry ;;
	--scoped) mode=scoped ;;
	--prove)
		mode=prove
		[ -n "${2:-}" ] || usage
		prove_slug="$2"
		shift
		;;
	*) usage ;;
	esac
	shift
	while [ "$#" -gt 0 ]; do
		case "$mode:$1" in
		registry:--scope)
			[ -n "${2:-}" ] || usage
			scope_file="$2"
			shift 2
			;;
		scoped:--paths)
			[ -n "${2:-}" ] || usage
			paths_file="$2"
			shift 2
			;;
		*) usage ;;
		esac
	done
fi
fast=0
[ "$mode" = fast ] && fast=1

# Scope/paths lists: newline-delimited repo-relative paths, blank lines ignored.
# An explicit --scope beats $FORK_FLOW_GATE_SCOPE so a human CLI run is never
# silently narrowed by leftover environment. An EMPTY scope falls back to the
# FULL registry — a gate that verifies nothing must not exist. --scoped without
# --paths runs every entry's Test: (the manual "prove all targeted behavior" run).
scope_paths=""
if [ "$mode" = registry ]; then
	[ -z "$scope_file" ] && scope_file="${FORK_FLOW_GATE_SCOPE:-}"
	if [ -n "$scope_file" ]; then
		[ -f "$scope_file" ] || {
			printf 'verify.sh: scope file not found: %s\n' "$scope_file" >&2
			exit 2
		}
		scope_paths="$(awk 'NF' "$scope_file")"
		[ -z "$scope_paths" ] && printf 'note: scope file is empty — running the FULL registry\n' >&2
	fi
fi
sel_paths=""
if [ "$mode" = scoped ] && [ -n "$paths_file" ]; then
	[ -f "$paths_file" ] || {
		printf 'verify.sh: paths file not found: %s\n' "$paths_file" >&2
		exit 2
	}
	sel_paths="$(awk 'NF' "$paths_file")"
	[ -z "$sel_paths" ] && printf 'note: --paths file is empty — running every Test:\n' >&2
fi

have() { command -v "$1" >/dev/null 2>&1; }
run() {
	checked=1
	printf '+ %s\n' "$*" >&2
	"$@"
}
# Section timing: `timing: <name>=<N>s` on stderr for anything that took ≥1s
# (quiet for sub-second no-ops — these lines answer "where did the run go";
# port.sh run rolls them into its batch summary). Propagates the command's rc.
timed() { # <name> <command…>
	local _tn="$1" _t0 _t1 _rc=0
	shift
	# `date` can be missing on a deliberately restricted PATH (a shimmed CI/test
	# environment) — timings then silently disappear; the command itself MUST
	# still run and its rc still decide.
	_t0="$(date +%s 2>/dev/null || echo 0)"
	"$@" || _rc=$?
	_t1="$(date +%s 2>/dev/null || echo 0)"
	[ "$((_t1 - _t0))" -ge 1 ] && printf 'timing: %s=%ss\n' "$_tn" "$((_t1 - _t0))" >&2
	return "$_rc"
}
ran_something=0
checked=0 # set by run(); lets --fast warn when it actually verified nothing

# An install can side-effect git config: hook managers like husky re-point
# core.hooksPath from a `prepare` script, silently UN-WIRING the fork-flow hooks.
# Called right AFTER each stack's install step (the moment it can happen — an
# end-of-run-only warning is never reached when a heavy build runs long or hangs)
# and again at the end of a full run. Warn-only — verify decides nothing about
# config — and only once per run.
unwire_warned=0
warn_if_unwired() {
	[ "$mode" = full ] || return 0
	[ "$unwire_warned" = 1 ] && return 0
	[ -f .fork/hooks/_merge-gate ] || return 0
	hooks_gate_wired && return 0
	unwire_warned=1
	printf 'WARN: fork-flow hooks are NOT wired in this clone — a hook manager (husky?) may have\n' >&2
	printf '      re-pointed core.hooksPath during the install. Manual commits/merges are UNGATED\n' >&2
	printf '      until you re-run: ./.fork/setup.sh   (it chains the other manager'\''s hooks)\n' >&2
}

# --- merge=ours backstop (full runs only) -----------------------------------
guard_merge_ours() {
	[ -f .gitattributes ] || return 0
	failed=0
	while IFS= read -r path; do
		[ -z "$path" ] && continue
		# git ls-files honors pathspec/globs (e.g. "*.svg", "assets/**"), so a glob
		# override is satisfied as long as it still matches at least one tracked file.
		# (Matches brief.sh, which reads .gitattributes paths through git too.)
		if ! git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
			printf 'ERROR: .gitattributes lists %s as merge=ours but it matches no tracked file\n' "$path" >&2
			failed=1
		fi
	done < <(merge_ours_paths)
	return "$failed"
}

# Do the CURRENT entry's anchors (rtouches/rsymbols, set by verify_registry's
# field loop) glob-match ANY path in the newline list $1? Anchors are PATTERNS
# (Touches tokens + the @path part of each Symbols token); the list holds
# literal repo-relative paths — the same asymmetric matching as path_registered,
# reused so gate scoping can never disagree with audit/brief matching. Loop
# bodies use if/then (never a bare `[ … ] &&` tail) for set -e safety, matching
# brief.sh's flush().
entry_hits() {
	local anchors s p
	anchors="$({
		split_field "$rtouches"
		split_field "$rsymbols" | while IFS= read -r s; do symbol_path "$s"; done
	} | awk 'NF && !seen[$0]++')"
	[ -z "$anchors" ] && return 1
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		if path_registered "$p" "$anchors"; then return 0; fi
	done <<EOF
$1
EOF
	return 1
}

# --- per-customization checks (full + --registry runs) -----------------------
# Run the Verify of EVERY registry entry, not just ones with a Drift-if: a
# silently dropped customization usually has no Drift-if, and skipping its Verify
# is exactly how that drop slips through the gate. The KIND of Verify is decided by
# its first token, never guessed from the command name:
#   * "manual:" prefix  -> a human check; listed for you, never executed
#   * empty             -> no Verify; reported as not gated
#   * anything else      -> a runnable command; executed via bash -c, non-zero fails
# Treating everything unmarked as runnable means env-prefixed ("NODE_ENV=test npm
# test") and variable ("$PM run test") commands run correctly; a human check must
# mark itself "manual:". An unmarked prose Verify runs, fails, and is flagged with a
# hint — never silently skipped. A Drift-if names a SILENT-breakage risk that a
# manual or missing Verify cannot catch, so either combination is a hard error.
# This is what proves YOUR customizations survived an upstream merge — upstream's
# own tests usually do not exercise them, and the worst changes produce NO conflict.
verify_registry() {
	local changes=".fork/CHANGES.md"
	[ -f "$changes" ] || return 0
	# Fail loudly on a malformed registry heading (a "## " typo'd to "##slug", or an
	# empty "## ") instead of silently dropping or mis-attributing a Verify. A field
	# before the first heading only warns (the parser already ignores it).
	registry_lint "$changes" || return 1
	# Anchor honesty at write time (audit's orphaned-anchors check, run by the gate so
	# a bad anchor is caught when it is WRITTEN, not at the next audit): an anchor that
	# matches no tracked file protects nothing — usually a typo, prose that leaked into
	# the field, or a comma-split fragment ("file.ts (foo, bar)" splits into three bogus
	# anchors, and brief.sh then reports a false "(no entries match)" for the real file).
	# WARN, never fail: during fork-change the gate legitimately runs before a brand-new
	# file is staged (git ls-files reads the index), and a port may legitimately delete
	# an anchored file mid-resolution. Literal match first (grep -Fx, covers real paths
	# containing glob chars), then the kit's own glob matching — so this can never
	# disagree with audit/brief.
	local tracked p
	tracked="$(git ls-files)"
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		if printf '%s\n' "$tracked" | grep -Fxq -- "$p"; then continue; fi
		if glob_match_any "$p" "$tracked"; then continue; fi
		printf 'WARN: registry anchor matches no tracked file (typo? comma-split fragment? not yet staged?): %s\n' "$p" >&2
	done < <(registry_paths "$changes")
	# Delta-tripwire base: the porting pointer, computed ONCE per run (not per
	# entry). Empty/unresolvable pointer disables the tripwire quietly.
	local tripwire_ptr
	tripwire_ptr="$(upstream_pointer)"
	if [ -n "$tripwire_ptr" ] && ! git rev-parse --verify --quiet "${tripwire_ptr}^{commit}" >/dev/null 2>&1; then
		tripwire_ptr=""
	fi
	rheading=""
	rdrift=""
	rverify=""
	rtouches=""
	rsymbols=""
	rtest=""
	rfailed=0
	manual=""
	unprot=""
	untested=""
	check_entry() {
		[ -z "$rheading" ] && return 0
		# A scoped GATE run (port.sh's per-commit hook during a batch) SKIPS an
		# entry whose anchors match none of the commit's paths — no Verify run, no
		# manual/unprot listing; the batch end runs --scoped, which executes and
		# lists the FULL set. An empty scope never reaches here (it fell back to
		# the full registry at load time), so this can never skip everything.
		if [ "$mode" = registry ] && [ -n "$scope_paths" ] && ! entry_hits "$scope_paths"; then
			rheading="" rdrift="" rverify="" rtouches="" rsymbols="" rtest=""
			return 0
		fi
		local v rc t0 t1 tcmd trc tt0 tt1 tw_t tw_tokens
		# Path-level delta TRIPWIRE (warn-only, LOW SPECIFICITY — never proof): an
		# entry whose Touches anchors show NO diff against the porting base has no
		# fork delta left anywhere under those paths — the customization may be
		# gone, or upstream now ships it (then retire it via drop-change). An
		# anchor overlapping ANOTHER entry's delta keeps this green, so silence
		# here detects only total path-level loss. Entries with only Symbols
		# anchors are skipped: symbol paths alone are not delta anchors. Warn-only
		# because superseded-then-retire is a legitimate state that must not block
		# a batch. Touches tokens are git pathspecs (the established convention);
		# a token matching nothing yields an empty diff, which the orphaned-anchor
		# warning above already surfaces.
		if [ -n "$tripwire_ptr" ] && [ -n "$rtouches" ]; then
			tw_tokens=()
			while IFS= read -r tw_t; do
				[ -n "$tw_t" ] && tw_tokens+=("$tw_t")
			done < <(split_field "$rtouches")
			if [ "${#tw_tokens[@]}" -gt 0 ]; then
				if git diff --quiet "$tripwire_ptr" HEAD -- "${tw_tokens[@]}" 2>/dev/null; then
					printf 'WARN: no fork delta remains across the anchors of "%s" (path-level tripwire, low specificity when anchors overlap other entries) — the customization may be gone or upstream now ships it: drift-check, and retire with drop-change if superseded\n' "$rheading" >&2
				fi
			fi
		fi
		v="${rverify#"${rverify%%[![:space:]]*}"}" # Verify value, leading whitespace trimmed
		case "$v" in
		[Mm]anual:*)
			if [ -n "$rdrift" ]; then
				printf 'ERROR: customization "%s" has a Drift-if but its Verify is marked manual — it must be a runnable command\n' "$rheading" >&2
				rfailed=1
			else
				manual="${manual:+$manual
}$rheading"
			fi
			;;
		"")
			if [ -n "$rdrift" ]; then
				printf 'ERROR: customization "%s" declares a Drift-if but has no Verify command\n' "$rheading" >&2
				rfailed=1
			else
				unprot="${unprot:+$unprot
}$rheading"
			fi
			;;
		*)
			ran_something=1
			printf '+ verify[%s]:%s\n' "$rheading" "$rverify" >&2
			# Redirect stdin from /dev/null: a Verify that reads stdin (cat, grep PAT,
			# sort, a read-based script, ssh/docker run without -t) would otherwise
			# inherit this loop's stdin (CHANGES.md, via `done < "$changes"`) and swallow
			# every following entry, so the gate would skip those checks and exit OK.
			rc=0
			t0="$(date +%s)"
			bash -c "$rverify" </dev/null || rc=$?
			t1="$(date +%s)"
			# BUDGET tripwire: the gate runs EVERY entry's Verify on EVERY integration
			# commit — one slow Verify teaches everyone FORK_SKIP_VERIFY, which kills
			# all protection. Warn (never fail) past 2s; the fix is moving the slow
			# suite into the project's own test script (the full-gate path).
			if [ "$((t1 - t0))" -ge 2 ]; then
				printf 'WARN: Verify of "%s" took ~%ss — keep each Verify sub-second and install-free (the gate runs every Verify on every integration commit; slow suites belong in the project'\''s own test script, not a Verify)\n' "$rheading" "$((t1 - t0))" >&2
			fi
			if [ "$rc" -ne 0 ]; then
				printf 'ERROR: customization "%s" failed its Verify (exit %s)\n' "$rheading" "$rc" >&2
				if [ "$rc" -eq 127 ]; then
					printf '       (if this is a human check, prefix the Verify with "manual:" so the gate lists it instead of running it)\n' >&2
				fi
				rfailed=1
			fi
			;;
		esac
		# --scoped: additionally run the entry's targeted Test: when the entry is
		# TOUCHED (--paths), or for every entry when --paths was not given. A
		# touched entry with NO Test: is reported below — the scoped run proved its
		# presence (Verify) but not its behavior; the CI full gate covers that. No
		# 2s tripwire here: a targeted suite may legitimately take seconds.
		if [ "$mode" = scoped ]; then
			if [ -z "$sel_paths" ] || entry_hits "$sel_paths"; then
				tcmd="${rtest#"${rtest%%[![:space:]]*}"}"
				if [ -n "$tcmd" ]; then
					ran_something=1
					printf '+ test[%s]:%s\n' "$rheading" "$rtest" >&2
					trc=0
					tt0="$(date +%s 2>/dev/null || echo 0)"
					bash -c "$rtest" </dev/null || trc=$?
					tt1="$(date +%s 2>/dev/null || echo 0)"
					printf 'timing: test[%s]=%ss\n' "$rheading" "$((tt1 - tt0))" >&2
					if [ "$trc" -ne 0 ]; then
						printf 'ERROR: customization "%s" failed its Test (exit %s)\n' "$rheading" "$trc" >&2
						rfailed=1
					fi
				else
					untested="${untested:+$untested
}$rheading"
				fi
			fi
		fi
		rheading=""
		rdrift=""
		rverify=""
		rtouches=""
		rsymbols=""
		rtest=""
	}
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		"## "*)
			check_entry
			rheading="${line#"## "}"
			;;
		# Only capture fields once a heading is open, so a stray field BEFORE the first
		# "## " (which registry_lint warns about) is truly ignored, not carried into the
		# first entry. Matches registry_paths_stream's entry-aware parsing.
		[Dd]rift-if:*) [ -n "$rheading" ] && rdrift="${line#*:}" ;;
		[Tt]ouches:*) [ -n "$rheading" ] && rtouches="${line#*:}" ;;
		[Ss]ymbols:*) [ -n "$rheading" ] && rsymbols="${line#*:}" ;;
		[Tt]est:*) [ -n "$rheading" ] && rtest="${line#*:}" ;;
		[Vv]erify:*) [ -n "$rheading" ] && rverify="${line#*:}" ;;
		esac
	done <"$changes"
	check_entry
	if [ -n "$manual" ]; then
		printf 'verify by hand (Verify marked manual:) — confirm these survived:\n' >&2
		printf '%s\n' "$manual" | while IFS= read -r m; do [ -n "$m" ] && printf '  - %s\n' "$m" >&2; done
	fi
	if [ -n "$unprot" ]; then
		printf 'note: customizations with NO Verify (the gate cannot prove these survived):\n' >&2
		printf '%s\n' "$unprot" | while IFS= read -r u; do [ -n "$u" ] && printf '  - %s\n' "$u" >&2; done
	fi
	if [ -n "$untested" ]; then
		printf 'note: touched customizations with NO Test: (presence verified, behavior NOT):\n' >&2
		printf '%s\n' "$untested" | while IFS= read -r u; do [ -n "$u" ] && printf '  - %s\n' "$u" >&2; done
	fi
	return "$rfailed"
}

# --- Node --------------------------------------------------------------------
# Which package manager does the repo PIN (a committed lockfile or a packageManager
# field)? A pin is authoritative: when the pinned binary is missing we REFUSE rather
# than fall back to npm — npm would re-resolve the whole tree with the wrong resolver
# on exactly the repo class that pinned its manager (lockfile discipline cuts both
# ways). Echoes the pin name, or nothing for an unpinned repo.
node_pm_pinned() {
	if [ -f bun.lock ] || [ -f bun.lockb ] || grep -q '"packageManager"[[:space:]]*:[[:space:]]*"bun' package.json 2>/dev/null; then
		echo bun
	elif [ -f pnpm-lock.yaml ] || grep -q '"packageManager"[[:space:]]*:[[:space:]]*"pnpm' package.json 2>/dev/null; then
		echo pnpm
	elif [ -f yarn.lock ] || grep -q '"packageManager"[[:space:]]*:[[:space:]]*"yarn' package.json 2>/dev/null; then
		echo yarn
	elif [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
		echo npm
	fi
}
# Echo the package manager to USE. Returns 1 (with the refusal on stderr) when the
# repo pins a manager whose binary is missing; echoes nothing when no manager at all
# is available on an unpinned repo (the caller notes-and-skips that case).
node_pm() {
	local pinned
	pinned="$(node_pm_pinned)"
	if [ -n "$pinned" ]; then
		if have "$pinned"; then
			echo "$pinned"
			return 0
		fi
		printf 'ERROR: this repo pins %s (lockfile/packageManager) but no %s binary is on PATH —\n' "$pinned" "$pinned" >&2
		printf '       refusing to fall back to npm (a different resolver would rewrite the dependency\n' >&2
		printf '       tree the lockfile pins). Install it (corepack enable, or npm i -g %s) and re-run.\n' "$pinned" >&2
		return 1
	fi
	if have npm; then echo npm; fi
	return 0
}
node_has_script() { # <script-name>
	have node || return 1
	FF_SCRIPT_NAME="$1" node -e 'const s=(require("./package.json").scripts)||{};process.exit(s[process.env.FF_SCRIPT_NAME]?0:1)' 2>/dev/null
}
bun_has_script() { # <script-name>
	have bun || return 1
	FF_SCRIPT_NAME="$1" bun -e 'const s=(require("./package.json").scripts)||{};process.exit(s[process.env.FF_SCRIPT_NAME]?0:1)' 2>/dev/null
}
pm_has_script() { # <pm> <script-name>
	case "$1" in
	bun) bun_has_script "$2" || node_has_script "$2" ;;
	*) node_has_script "$2" ;;
	esac
}
verify_node() {
	[ -f package.json ] || return 0
	# node_pm REFUSES (rc 1 + message) on a pinned-but-missing manager — that must FAIL
	# the gate, not skip the stack: skipping would print OK having verified nothing on
	# exactly the repos that care most about their resolver.
	pm="$(node_pm)" || return 1
	[ -z "$pm" ] && {
		printf 'note: package.json present but no node package manager found\n' >&2
		return 0
	}
	ran_something=1
	if [ "$fast" = 1 ]; then
		pm_has_script "$pm" typecheck && run "$pm" run typecheck
		return 0
	fi
	# Prefer a frozen install for reproducibility, but fall back to a normal install
	# when no lockfile is committed yet — otherwise a fresh fork fails before it ever
	# reaches the registry Verifies (npm ci hard-requires a lockfile).
	case "$pm" in
	bun) if [ -f bun.lock ] || [ -f bun.lockb ]; then
		run bun install --frozen-lockfile
	else
		printf 'note: no bun lockfile — installing without --frozen-lockfile\n' >&2
		run bun install
	fi ;;
	pnpm) if [ -f pnpm-lock.yaml ]; then
		run pnpm install --frozen-lockfile
	else
		printf 'note: no pnpm-lock.yaml — installing without --frozen-lockfile\n' >&2
		run pnpm install
	fi ;;
	yarn) if [ -f yarn.lock ]; then
		run yarn install --frozen-lockfile
	else
		printf 'note: no yarn.lock — installing without --frozen-lockfile\n' >&2
		run yarn install
	fi ;;
	npm) if [ -f package-lock.json ] || [ -f npm-shrinkwrap.json ]; then
		run npm ci
	else
		printf 'note: no package-lock.json — using npm install (npm ci requires a lockfile)\n' >&2
		run npm install
	fi ;;
	esac
	# The install that just ran is the one that can re-point core.hooksPath (husky's
	# `prepare` runs on every install). Check NOW, not only at the end of the run — on
	# a heavy project lint/test/build may run for many minutes (or never finish in this
	# environment), and an end-of-run-only warning is then never reached.
	warn_if_unwired
	for s in typecheck lint test build; do
		pm_has_script "$pm" "$s" && run "$pm" run "$s"
	done
	return 0
}

# --- Rust --------------------------------------------------------------------
verify_rust() {
	[ -f Cargo.toml ] || return 0
	have cargo || {
		printf 'note: Cargo.toml present but cargo not found\n' >&2
		return 0
	}
	ran_something=1
	if [ "$fast" = 1 ]; then
		run cargo check --all-targets
		return 0
	fi
	run cargo build --all-targets --locked
	have cargo-clippy && run cargo clippy --all-targets -- -D warnings
	run cargo test --locked
	return 0
}

# --- Python ------------------------------------------------------------------
verify_python() {
	{ [ -f pyproject.toml ] || [ -f requirements.txt ]; } || return 0
	ran_something=1
	runner=""
	if have uv; then
		runner="uv run"
	elif have poetry && [ -f poetry.lock ]; then
		runner="poetry run"
	fi
	if [ "$fast" = 1 ]; then
		if have pyright; then
			run pyright
		elif [ -n "$runner" ] && $runner python -c 'import mypy' >/dev/null 2>&1; then
			run $runner mypy .
		fi
		return 0
	fi
	if [ -n "$runner" ]; then
		run $runner pytest -q
	elif have pytest; then
		run pytest -q
	else
		printf 'note: python project but no pytest/uv/poetry runner found\n' >&2
	fi
	return 0
}

# --- PHP / Laravel -----------------------------------------------------------
# Laravel/Symfony/plain-Composer all share composer.json. We detect Laravel by its
# `artisan` console so `php artisan test` is preferred there; otherwise fall back to
# a composer "test" script, then pest/phpunit directly.
php_composer_script() { # <script-name>
	have php || return 1
	[ -f composer.json ] || return 1
	# shellcheck disable=SC2016  # $j/$argv are PHP vars, single-quoted on purpose
	php -r '$j=json_decode(file_get_contents("composer.json"),true);exit(isset($j["scripts"][$argv[1]])?0:1);' "$1" 2>/dev/null
}
verify_php() {
	[ -f composer.json ] || return 0
	have composer || {
		printf 'note: composer.json present but composer not found\n' >&2
		return 0
	}
	ran_something=1
	if [ "$fast" = 1 ]; then
		# No native typecheck in PHP; use a static analyzer if the fork wired one in.
		if [ -x vendor/bin/phpstan ]; then
			run vendor/bin/phpstan analyse --no-progress
		elif [ -x vendor/bin/psalm ]; then
			run vendor/bin/psalm --no-progress
		fi
		return 0
	fi
	# Prefer a reproducible install when composer.lock is committed.
	if [ -f composer.lock ]; then
		run composer install --no-interaction --no-progress --prefer-dist
	else
		printf 'note: no composer.lock — installing without a locked set\n' >&2
		run composer install --no-interaction --no-progress
	fi
	warn_if_unwired # an install script could have re-pointed core.hooksPath (see top)
	[ -x vendor/bin/pint ] && run vendor/bin/pint --test
	[ -x vendor/bin/phpstan ] && run vendor/bin/phpstan analyse --no-progress
	if php_composer_script test; then
		run composer run-script test
	elif [ -f artisan ]; then
		run php artisan test
	elif [ -x vendor/bin/pest ]; then
		run vendor/bin/pest
	elif [ -x vendor/bin/phpunit ]; then
		run vendor/bin/phpunit
	else
		printf 'note: composer project but no test script/pest/phpunit found\n' >&2
	fi
	return 0
}

# --- Ruby / Rails ------------------------------------------------------------
# Rails is just a Gemfile + bin/rails; we run rspec when there's a spec/ dir,
# otherwise the rake/rails test task. Sorbet's `srb tc` is the closest thing to a
# typecheck for --fast, used only if the fork adopted it.
verify_ruby() {
	[ -f Gemfile ] || return 0
	have bundle || {
		printf 'note: Gemfile present but bundler not found\n' >&2
		return 0
	}
	ran_something=1
	if [ "$fast" = 1 ]; then
		# Probe that `srb` actually RUNS before gating on it: `bundle show sorbet` can be
		# satisfied by a globally-visible gem on a project that does not use Sorbet at
		# all, and an unguarded `bundle exec srb tc` then dies 127 under set -e — the
		# quick-feedback mode crashing with no verdict line (seen on a real Rails fork).
		# A probe failure SKIPS the check (the summary still says nothing was verified);
		# only a real typecheck failure may fail fast mode.
		if bundle show sorbet >/dev/null 2>&1; then
			if bundle exec srb --version >/dev/null 2>&1; then
				run bundle exec srb tc
			else
				printf 'note: sorbet gem visible but srb is not runnable here — skipping typecheck (bundle install?)\n' >&2
			fi
		fi
		return 0
	fi
	# bundle check avoids a slow reinstall when the gems are already satisfied.
	bundle check >/dev/null 2>&1 || run bundle install
	warn_if_unwired # an install hook could have re-pointed core.hooksPath (see top)
	bundle show rubocop >/dev/null 2>&1 && run bundle exec rubocop
	if [ -d spec ] && bundle show rspec-core >/dev/null 2>&1; then
		run bundle exec rspec
	elif [ -f bin/rails ]; then
		run bin/rails test
	elif bundle show rake >/dev/null 2>&1; then
		run bundle exec rake test
	else
		printf 'note: Ruby project but no rspec/rails/rake test runner found\n' >&2
	fi
	return 0
}

# --- Swift -------------------------------------------------------------------
# SwiftPM only (Package.swift). Apps that are .xcodeproj/.xcworkspace-only need a
# scheme + xcodebuild invocation that varies per project, so wire those into a
# registry Verify instead of guessing a scheme here.
verify_swift() {
	[ -f Package.swift ] || return 0
	have swift || {
		printf 'note: Package.swift present but swift toolchain not found\n' >&2
		return 0
	}
	ran_something=1
	# `swift build` IS the typecheck/compile for SwiftPM, so it covers --fast too.
	run swift build
	[ "$fast" = 1 ] && return 0
	run swift test
	return 0
}

# --prove <slug>: MECHANIZED watched-failure proof for a COMMITTED customization.
# Reverts the entry's Touches paths to their porting-base copies (a net-new file
# is deleted — absence IS the base state), runs the entry's Verify (it must
# FAIL), restores everything, re-runs (it must PASS). A Verify that passes with
# the customization removed protects nothing. Requires a clean tree (the restore
# must be exact) and a resolvable pointer (the proof needs the porting base).
# The Drift-if half of the proof (stubbing the upstream symbol) stays manual.
# PROVE_RESTORE is a GLOBAL (not local) so the EXIT trap can restore the anchor
# paths even when an intermediate step dies under set -e.
PROVE_RESTORE=()
verify_prove() { # <slug>
	local slug="$1" ptr line h in_entry=0 ptouches="" pverify="" pdrift="" v tok f
	local matched base_rc=0 rest_rc=0
	if ! git diff --quiet || ! git diff --cached --quiet; then
		printf 'ERROR: --prove needs a CLEAN tree (it reverts and restores anchor paths; the restore must be exact) — commit or stash first\n' >&2
		return 1
	fi
	ptr="$(upstream_pointer)"
	if [ -z "$ptr" ] || ! git rev-parse --verify --quiet "${ptr}^{commit}" >/dev/null 2>&1; then
		printf 'ERROR: --prove needs a resolvable .fork/UPSTREAM pointer (the proof reverts anchors to the porting base)\n' >&2
		return 1
	fi
	if [ ! -f .fork/CHANGES.md ]; then
		printf 'ERROR: no .fork/CHANGES.md — nothing to prove\n' >&2
		return 1
	fi
	# Collect the entry's fields (the same entry-aware loop as verify_registry).
	while IFS= read -r line || [ -n "$line" ]; do
		case "$line" in
		"## "*)
			[ "$in_entry" = 1 ] && break
			h="${line#"## "}"
			if [ "$h" = "custom: $slug" ] || [ "$h" = "$slug" ]; then in_entry=1; fi
			;;
		[Tt]ouches:*) [ "$in_entry" = 1 ] && ptouches="${line#*:}" ;;
		[Vv]erify:*) [ "$in_entry" = 1 ] && pverify="${line#*:}" ;;
		[Dd]rift-if:*) [ "$in_entry" = 1 ] && pdrift="${line#*:}" ;;
		esac
	done <.fork/CHANGES.md
	if [ "$in_entry" = 0 ]; then
		printf 'ERROR: no entry "## custom: %s" in .fork/CHANGES.md\n' "$slug" >&2
		return 1
	fi
	v="${pverify#"${pverify%%[![:space:]]*}"}"
	case "$v" in
	"" | [Mm]anual:*)
		printf 'ERROR: the Verify of "%s" is %s — nothing to prove mechanically\n' "$slug" "$([ -z "$v" ] && echo 'empty' || echo 'manual:')" >&2
		return 1
		;;
	esac
	if [ -z "$ptouches" ]; then
		printf 'ERROR: "%s" has no Touches anchors — nothing to revert for the proof\n' "$slug" >&2
		return 1
	fi
	# Expand Touches against tracked files (literal first, then glob — the kit's
	# one matching order), de-duplicated.
	matched="$(
		tracked="$(git ls-files)"
		while IFS= read -r tok; do
			[ -z "$tok" ] && continue
			while IFS= read -r f; do
				[ -z "$f" ] && continue
				if glob_match "$tok" "$f"; then printf '%s\n' "$f"; fi
			done <<EOF2
$tracked
EOF2
		done < <(split_field "$ptouches") | awk 'NF && !seen[$0]++'
	)"
	if [ -z "$matched" ]; then
		printf 'ERROR: the Touches anchors of "%s" match no tracked file — nothing to prove against\n' "$slug" >&2
		return 1
	fi
	PROVE_RESTORE=()
	while IFS= read -r f; do
		[ -n "$f" ] && PROVE_RESTORE+=("$f")
	done <<EOF2
$matched
EOF2
	# ANY death from here on still restores: the trap re-checks out every matched
	# path from HEAD (which also restores tracked deletions).
	trap 'git checkout HEAD -- "${PROVE_RESTORE[@]}" >/dev/null 2>&1 || true' EXIT
	for f in "${PROVE_RESTORE[@]}"; do
		if git cat-file -e "$ptr:$f" 2>/dev/null; then
			git checkout "$ptr" -- "$f" # revert to the porting-base copy
		else
			rm -f "$f" # net-new file: absence IS the base state
		fi
	done
	printf '+ prove[%s] Verify on the BASE state (must fail):%s\n' "$slug" "$pverify" >&2
	bash -c "$pverify" </dev/null >/dev/null 2>&1 || base_rc=$?
	git checkout HEAD -- "${PROVE_RESTORE[@]}"
	printf '+ prove[%s] Verify on the RESTORED state (must pass):%s\n' "$slug" "$pverify" >&2
	bash -c "$pverify" </dev/null >/dev/null 2>&1 || rest_rc=$?
	trap - EXIT
	if [ "$base_rc" -eq 0 ]; then
		printf 'PROOF FAILED: the Verify of "%s" PASSES with the customization removed — it protects nothing; rewrite it to assert the real value/shape\n' "$slug" >&2
		return 1
	fi
	if [ "$rest_rc" -ne 0 ]; then
		printf 'ERROR: the Verify of "%s" FAILS on the restored tree (exit %s) — the tree was restored; the Verify itself is broken\n' "$slug" "$rest_rc" >&2
		return 1
	fi
	printf 'PROOF OK: %s — Verify fails without the customization and passes with it\n' "$slug"
	if [ -n "$pdrift" ]; then
		printf 'note: the Drift-if half of the proof (stub the upstream symbol, watch the Verify fail) stays manual\n' >&2
	fi
	return 0
}
if [ "$mode" = prove ]; then
	# Called UNGUARDED on purpose: an `|| exit` here would disable errexit inside
	# the function, letting an intermediate checkout/rm failure slip past the
	# restore guarantees. A non-zero return (verdict or error) exits the script
	# with that status under set -e; the EXIT trap covers intermediate deaths.
	verify_prove "$prove_slug"
	exit 0
fi

# --registry: just the checks that prove YOUR customizations survived — the
# merge=ours backstop and the registry Verifies — with no install/build, so it
# answers "did my changes survive?" even when the merged build is still red.
# With a scope (--scope / $FORK_FLOW_GATE_SCOPE) only entries whose anchors
# match a scoped path run — port.sh's cheap per-commit gate during a batch; the
# batch end re-verifies the FULL set via --scoped.
if [ "$mode" = registry ]; then
	guard_merge_ours || exit 1
	timed registry verify_registry || exit 1
	[ "$ran_something" = 0 ] && printf 'note: no runnable Verifies ran.\n' >&2
	if [ -n "$scope_paths" ]; then
		printf 'verify.sh: OK (registry, scoped: %s path(s))\n' "$(printf '%s\n' "$scope_paths" | grep -c .)" >&2
	else
		printf 'verify.sh: OK (registry)\n' >&2
	fi
	exit 0
fi

# --scoped: the fast LOCAL behavior check after a port run — the FULL registry
# (every Verify, exactly like --registry) PLUS each touched entry's Test: (its
# targeted project tests). No install/lint/build: it assumes the worked-in tree
# you just ported on; the from-scratch proof is the full gate, which the shipped
# CI workflow re-runs on push.
if [ "$mode" = scoped ]; then
	guard_merge_ours || exit 1
	timed registry verify_registry || exit 1
	[ "$ran_something" = 0 ] && printf 'note: no runnable Verifies or Test: commands ran.\n' >&2
	printf 'verify.sh: OK (scoped)\n' >&2
	exit 0
fi

if [ "$fast" = 0 ]; then
	guard_merge_ours || exit 1
fi
timed node verify_node
timed rust verify_rust
timed python verify_python
timed php verify_php
timed ruby verify_ruby
timed swift verify_swift
if [ "$fast" = 0 ]; then
	timed registry verify_registry || exit 1
fi

if [ "$ran_something" = 0 ]; then
	printf 'note: no recognized stack to verify (no package.json/Cargo.toml/pyproject.toml/composer.json/Gemfile/Package.swift).\n' >&2
	if [ "$fast" = 0 ]; then
		printf '      merge=ours backstop checked; wire stack commands into .fork/verify.sh once a stack exists.\n' >&2
	else
		printf '      wire stack commands into .fork/verify.sh once a stack exists.\n' >&2
	fi
elif [ "$fast" = 1 ] && [ "$checked" = 0 ]; then
	printf 'note: --fast found a stack but ran no check (e.g. no "typecheck" script) — NOTHING was verified.\n' >&2
fi
# End-of-run backstop for the same install side-effect (warn_if_unwired already fired
# right after each install step; this catches a non-node stack's install or any later
# re-point). Warn-only; at most one warning per run.
warn_if_unwired
printf 'verify.sh: OK%s\n' "$([ "$fast" = 1 ] && echo ' (fast)')" >&2
