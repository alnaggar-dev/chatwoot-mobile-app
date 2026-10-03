# .superflow/project.sh — the project's half of the SuperFlow scripts. Project-owned: the
# SuperFlow kit's install.sh seeds it once and never overwrites it.
#
# Sourced from the repository root, under `set -euo pipefail` and macOS /bin/bash 3.2, by
#   .superflow/bin/near-tests.sh   (uses sf_tests_for, sf_run_tests)
#   .superflow/bin/fingerprint.sh  (uses SF_FINGERPRINT_FILES)
#   .superflow/bin/full-suite.sh   (uses SF_FINGERPRINT_FILES)
# Define only these three names; no side effects at source time.
#
# Fill in both functions and delete the unfilled-marker comment inside each once it is real.
# Until then they print "fill in .superflow/project.sh" and return 2, so near-tests fails
# loudly instead of passing green on nothing. Examples for several stacks are at the bottom:
# copy one over the defaults and adjust its paths.

# Untracked config files that change app behavior (space-separated, repo-relative, globs
# allowed). fingerprint.sh hashes each one that exists, so evidence and reviews go stale when
# they change; full-suite.sh copies them into its throwaway worktree.
SF_FINGERPRINT_FILES=".env"

# sf_tests_for <path>
#   <path> is one repo-relative path from the change set (it may be deleted). Print the
#   candidate test files for it, one per line; print nothing when it has none. A test file
#   maps to itself. Candidates need not exist: near-tests keeps only files on disk. Return 0.
sf_tests_for() {
	# Jest specs live in a specs/ folder beside the module: src/utils/rtlUtils.ts →
	# src/utils/specs/rtlUtils.spec.ts (a .tsx module may have a .spec.ts or .spec.tsx).
	case "$1" in
	src/*/specs/*.spec.ts | src/*/specs/*.spec.tsx) printf '%s\n' "$1" ;;
	src/*.ts | src/*.tsx)
		local d b
		d="$(dirname "$1")"; b="$(basename "$1")"; b="${b%.*}"
		printf '%s/specs/%s.spec.ts\n%s/specs/%s.spec.tsx\n' "$d" "$b" "$d" "$b" ;;
	esac
}

# sf_run_tests <file>…
#   Run the given test files (at least one) in one go when the runner allows it. Return
#   non-zero when any test fails.
sf_run_tests() { pnpm test -- "$@"; }

# --- Examples (copy one stack's pair over the defaults above; mix cases for a polyglot repo) ---
#
# Rails (RSpec): app/models/user.rb → spec/models/user_spec.rb; lib/x.rb → spec/lib/x_spec.rb
# sf_tests_for() {
# 	case "$1" in
# 	spec/*_spec.rb) printf '%s\n' "$1" ;;
# 	app/*.rb) p="${1#app/}"; printf 'spec/%s_spec.rb\n' "${p%.rb}" ;;
# 	lib/*.rb) printf 'spec/%s_spec.rb\n' "${1%.rb}" ;;
# 	esac
# }
# sf_run_tests() { bundle exec rspec "$@"; }
#
# Laravel (PHPUnit or Pest): app/Models/User.php → tests/Unit/Models/UserTest.php
#                                                 | tests/Feature/Models/UserTest.php
# sf_tests_for() {
# 	case "$1" in
# 	tests/*Test.php) printf '%s\n' "$1" ;;
# 	app/*.php) p="${1#app/}"; p="${p%.php}"; printf 'tests/Unit/%sTest.php\ntests/Feature/%sTest.php\n' "$p" "$p" ;;
# 	esac
# }
# sf_run_tests() {  # one file per run: older PHPUnit takes a single path
# 	local f s=0
# 	for f in "$@"; do php artisan test "$f" || s=1; done
# 	return "$s"
# }
#
# Plain PHP (PHPUnit): src/Billing/Invoice.php → tests/Billing/InvoiceTest.php
# sf_tests_for() {
# 	case "$1" in
# 	tests/*Test.php) printf '%s\n' "$1" ;;
# 	src/*.php) p="${1#src/}"; printf 'tests/%sTest.php\n' "${p%.php}" ;;
# 	esac
# }
# sf_run_tests() {
# 	local f s=0
# 	for f in "$@"; do vendor/bin/phpunit "$f" || s=1; done
# 	return "$s"
# }
#
# Next.js / TypeScript (Vitest or Jest): src/lib/price.ts → src/lib/price.test.ts
#                                                         | src/lib/__tests__/price.test.ts
# sf_tests_for() {
# 	case "$1" in
# 	*.test.ts | *.test.tsx | *.spec.ts | *.spec.tsx) printf '%s\n' "$1" ;;
# 	src/*.ts | src/*.tsx)
# 		d="$(dirname "$1")"; b="$(basename "$1")"; e="${b##*.}"; b="${b%.*}"
# 		printf '%s/%s.test.%s\n%s/__tests__/%s.test.%s\n' "$d" "$b" "$e" "$d" "$b" "$e" ;;
# 	esac
# }
# sf_run_tests() { pnpm vitest run "$@"; }   # Jest: npx jest "$@"
#
# Node (node:test): lib/queue.js → test/queue.test.js
# sf_tests_for() {
# 	case "$1" in
# 	test/*.test.js) printf '%s\n' "$1" ;;
# 	lib/*.js) p="${1#lib/}"; printf 'test/%s.test.js\n' "${p%.js}" ;;
# 	esac
# }
# sf_run_tests() { node --test "$@"; }
#
# Python (pytest): pkg/billing/invoice.py → tests/test_invoice.py | tests/billing/test_invoice.py
# sf_tests_for() {
# 	case "$1" in
# 	tests/*test_*.py) printf '%s\n' "$1" ;;
# 	pkg/*.py)
# 		p="${1#pkg/}"; b="$(basename "$p" .py)"; d="$(dirname "$p")"
# 		printf 'tests/test_%s.py\n' "$b"
# 		[ "$d" = . ] || printf 'tests/%s/test_%s.py\n' "$d" "$b" ;;
# 	esac
# }
# sf_run_tests() { pytest "$@"; }
