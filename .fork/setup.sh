#!/usr/bin/env bash
# .fork/setup.sh: wire this clone's git config for the fork (idempotent).
#
#   ./.fork/setup.sh           apply the per-clone config
#   ./.fork/setup.sh --check   report the wiring, change nothing; exit 1 if anything is off
#
# git config is per clone; nothing in the repo carries it, so every clone runs this once.
# upstream-port runs --check before the Port preflight command.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

mode="${1:-}"
case "$mode" in
"" | --check) ;;
*)
	echo "usage: ./.fork/setup.sh [--check]" >&2
	exit 2
	;;
esac

mergiraf_driver='mergiraf merge --git %O %A %B -s %S -x %X -y %Y -p %P -l %L'
fallback_driver='git merge-file -L %X -L %S -L %Y %A %O %B'
gated_hooks="pre-commit pre-merge-commit commit-msg pre-push"
hm_dir=".hus""ky"

# The hooks dir to chain behind the gate, or nothing. Never the kit's own dir (that would
# recurse): resolved paths are compared, since a symlinked prefix can alias it.
detect_chain_dir() {
	local cur eff f self
	cur="$(git config --type=path core.hooksPath 2>/dev/null || true)"
	self="$(cd .fork/hooks 2>/dev/null && pwd -P)"
	if [ -n "$cur" ] && [ "$cur" != ".fork/hooks" ] &&
		[ "$(cd "$cur" 2>/dev/null && pwd -P)" != "$self" ]; then
		printf '%s' "$cur"
		return 0
	fi
	[ -z "$cur" ] || return 0
	# Default .git/hooks: chain only when a real (non-kit) hook there would be shadowed.
	# Absolute, so linked worktrees (other work trees, same hooks) run it too.
	eff="$(git rev-parse --path-format=absolute --git-path hooks 2>/dev/null)"
	if [ -n "$eff" ]; then
		for f in "$eff"/*; do
			[ -f "$f" ] && [ -x "$f" ] || continue
			case "${f##*/}" in *.sample) continue ;; esac
			if ! grep -qs 'fork-flow' "$f"; then
				printf '%s' "$eff"
				return 0
			fi
		done
	fi
	# A dormant hook manager: the project's committed hooks dir (the npm hook manager's
	# dot-dir, spelled split so the kit's stack-name check stays clean) before any install
	# pointed core.hooksPath at it.
	for f in "$hm_dir"/*; do
		if [ -f "$f" ] && ! grep -qs 'fork-flow' "$f"; then
			printf '%s' "$hm_dir"
			return 0
		fi
	done
	return 0
}

# Hooks in the chained dir with no .fork/hooks pass-through of the same name: they do not
# run while core.hooksPath is .fork/hooks.
unchained_hooks() { # DIR
	local d="$1" f out=""
	case "$d" in /*) ;; *) d="./$d" ;; esac
	for f in "$d"/*; do
		[ -f "$f" ] && [ -x "$f" ] || continue
		case "${f##*/}" in *.sample) continue ;; esac
		[ -x ".fork/hooks/${f##*/}" ] && continue
		out="$out ${f##*/}"
	done
	printf '%s' "${out# }"
}

rc=0
report() { # ok|MISSING|PROBLEM <text>
	printf '  %-8s %s\n' "$1" "$2"
	[ "$1" = ok ] || rc=1
}
chk_cfg() { # KEY WANTED LABEL
	local cur
	cur="$(git config "$1" 2>/dev/null || true)"
	if [ "$cur" = "$2" ]; then report ok "$3"; else report MISSING "$3 (have: ${cur:-<unset>})"; fi
}

if [ "$mode" = --check ]; then
	hp="$(git config core.hooksPath 2>/dev/null || true)"
	missing=""
	for h in $gated_hooks _chain; do [ -x ".fork/hooks/$h" ] || missing="$missing $h"; done
	if [ "$hp" != .fork/hooks ]; then
		report MISSING "core.hooksPath .fork/hooks (have: ${hp:-<unset>}); commits and merges are ungated in this clone"
	elif [ -n "$missing" ]; then
		report MISSING "executable hooks:$missing"
	else
		report ok "core.hooksPath .fork/hooks (ledger gate)"
	fi
	chain="$(git config fork-flow.chainHooksDir 2>/dev/null || true)"
	[ -z "$chain" ] || report ok "chained hooks: $chain (run after the gate)"
	chk_cfg rerere.enabled true 'rerere.enabled'
	chk_cfg rerere.autoUpdate false 'rerere.autoUpdate false (replays stay unstaged)'
	chk_cfg merge.conflictStyle zdiff3 'merge.conflictStyle zdiff3'
	# merge.ours.driver must be unset in every config file (the `command` scope is a
	# `git -c` around this call, not a file). Exit 1 = unset; anything above is an error.
	get_rc=0
	ours_all="$(git config --show-scope --show-origin --get-all merge.ours.driver 2>/dev/null)" || get_rc=$?
	ours_src=""
	[ "$get_rc" -ne 0 ] || ours_src="$(printf '%s\n' "$ours_all" | awk -F'\t' '$1 != "command"')"
	if [ "$get_rc" -gt 1 ]; then
		report PROBLEM "merge.ours.driver not checked: git config exited $get_rc (--show-scope needs git 2.26+)"
	elif [ -z "$ours_src" ]; then
		report ok 'merge.ours.driver unset (upstream-port passes it per merge)'
	else
		report PROBLEM 'merge.ours.driver is set; ordinary merges silently keep one side of merge=ours paths:'
		printf '%s\n' "$ours_src" | awk -F'\t' '{printf "             %s  %s = %s\n", $1, $2, $3}'
		printf '           fix: ./.fork/setup.sh removes a local key; remove others by hand,\n'
		printf '                e.g. git config --global --unset-all merge.ours.driver\n'
	fi
	if command -v mergiraf >/dev/null 2>&1; then
		report ok 'mergiraf installed'
		chk_cfg merge.mergiraf.driver "$mergiraf_driver" 'merge.mergiraf driver'
	else
		report MISSING 'mergiraf not installed (install it, then re-run ./.fork/setup.sh); ports get far more conflicts without it'
		chk_cfg merge.mergiraf.driver "$fallback_driver" 'merge.mergiraf text fallback'
	fi
	git remote get-url upstream >/dev/null 2>&1 ||
		printf '  %-8s %s\n' NOTE "no 'upstream' remote; porting needs one: git remote add upstream <url>"
	if [ "$rc" -ne 0 ]; then
		echo "setup.sh: this clone is not fully wired; run ./.fork/setup.sh" >&2
	else
		echo "setup.sh: fully wired" >&2
	fi
	exit "$rc"
fi

# Replayed conflict resolutions stay unstaged so they get reviewed, whatever the
# global config says.
git config rerere.enabled true
git config rerere.autoUpdate false

# merge.ours.driver must stay unset: ordinary merges then text-merge AGENTS.md, and only
# upstream-port's merge turns the driver on (-c merge.ours.driver=true). Exit 5 = absent.
git config --local --unset-all merge.ours.driver || [ $? -eq 5 ]

git config merge.conflictStyle zdiff3

# .gitattributes routes some paths to the mergiraf driver: the real one when the binary
# is installed, else git's own text merge.
if command -v mergiraf >/dev/null 2>&1; then
	git config merge.mergiraf.name mergiraf
	git config merge.mergiraf.driver "$mergiraf_driver"
else
	git config merge.mergiraf.name 'mergiraf fallback'
	git config merge.mergiraf.driver "$fallback_driver"
	echo "setup.sh: mergiraf not installed; using git's text merge (install it and re-run)" >&2
fi

# The ledger gate hooks. A hooks dir already in use is recorded once in
# fork-flow.chainHooksDir; every hook in it keeps running through the same-named
# .fork/hooks pass-through (the gated hooks pre-commit, pre-merge-commit, commit-msg and pre-push
# after their gate).
chain="$(detect_chain_dir)"
if [ -n "$chain" ]; then
	git config fork-flow.chainHooksDir "$chain"
	live=""
	for f in "$chain"/*; do
		[ -f "$f" ] && [ -x "$f" ] || continue
		case "${f##*/}" in *.sample) ;; *) live=1 ;; esac
	done
	if [ -n "$live" ]; then
		echo "setup.sh: chaining the existing hooks in $chain: they keep running (pre-commit, pre-merge-commit, commit-msg and pre-push after the gate)"
	else
		echo "setup.sh: NOTE: chained $chain, but it holds no executable hook yet; install the project's dependencies, then re-run ./.fork/setup.sh"
	fi
fi
git config core.hooksPath .fork/hooks
chain="$(git config fork-flow.chainHooksDir 2>/dev/null || true)"
if [ -n "$chain" ]; then
	others="$(unchained_hooks "$chain")"
	[ -z "$others" ] || echo "setup.sh: NOTE: these hooks in $chain do not run while core.hooksPath is .fork/hooks: $others"
fi
if grep -qs "\"prepare\"[[:space:]]*:.*${hm_dir#.}" package.json; then
	echo "setup.sh: NOTE: the project's hook manager re-points core.hooksPath on dependency installs; re-run ./.fork/setup.sh after one"
fi
echo "setup.sh: clone wired."
