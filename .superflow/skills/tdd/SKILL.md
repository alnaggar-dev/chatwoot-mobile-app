---
name: tdd
description: Test-first red-green-refactor at a real seam, near tests only. Use when the user asks for test-first work, or when a bug has a cheap local test.
disable-model-invocation: true
---

# Test-driven development

Tests follow the Tests line of `rule://code-conventions`; commands are keys in `rule://commands` (**Test one file**, `.superflow/bin/near-tests.sh` for the near tests).

1. **List the behaviors** from the request or the brief's `## Done when` and `## Decisions` (never re-asked). Vague → critical paths only.
2. **One behavior per cycle:** write one test, see it fail for the right reason, write the least code to pass. Never write the tests first in bulk.
3. **Near tests only.** A red you did not cause in a file you run is still yours to report.
4. **Refactor on green**, rerunning the near tests.
5. **Report** the test that proves each behavior and the test files you ran, with results.
