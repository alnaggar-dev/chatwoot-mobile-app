---
name: verify
description: Prove every Done-when item of a feature's brief, in the browser or by its tests, and write $(git rev-parse --git-dir)/superflow/<slug>/verify/report.md. Flow step 7 calls it; a human may run it too. `diagnose` and `prototype` use steps 2–5.
disable-model-invocation: true
---

# Verify
From `diagnose` or `prototype`, use steps 2–5 as that skill needs; it owns the result, so no report.

The commands below are keys in `.omp/rules/commands.md`; a key that is `none` skips what it drives. Evidence goes under `v=$(git rev-parse --git-dir)/superflow/<slug>/verify`, never in the tree.

1. **Items.** `.superflow/bin/proof.sh stamp <slug> before` first. Read `features/<slug>/PRD.md`: your items are every `## Done when` line. `Proof: tests` items: run their test files with the **Test one file** command and save the output under `$v/`. `Proof: browser` items: one journey per user flow, covering every item; none → skip steps 2–5. Note what the journeys need besides the app: the UI for anything on screen, a background worker for a job, a public tunnel for an incoming callback.
2. **Start.** The **Health check** command; down or failing → the **Run app** command, or the fix the failing line names. The change adds migrations, or a check reports pending ones → the **Migrations** command before driving. Never drive while a check the journeys need fails.
   - The app's port (the **App URL**) held by something that is not this app → report the holder; leave it running. Killing it only after the operator's yes.
   - A change that needs a restart (the **Restart app** entry says which) → the **Restart app** command. Restart on your own only an app this session started; otherwise only after the operator's yes.
3. **Seed.** Existing data first. The setup comes from the feature doc's `### Browser journey:` block, run with the **Run a setup snippet** command; none → work it out with read-only checks through **Run a setup snippet**, and name every value you set. A changed default in a config file never reaches existing rows: check the row. Never overwrite keys or stored settings: a stored setting may win over the environment. After the **Seed data** command resets the database, rerun the setup of every feature the run touches.
4. **Drive.** omp's own browser at the **App URL**: `browser.open({ ..., app: { relay: false } })`, never the operator's own browser through the relay. Log in as the **Dev login** user. Click the real user path; selectors by role and visible text, then `data-testid` (the project's end-to-end page objects, if any, show working ones). Text or style changes: render each touched language.
5. **Proof.** The finished result on screen and in the stored rows, not a step on the way (a toast, a 200, a queued job). Screenshots and query output go under `$v/`. `tab.screenshot()` ignores `path`: it saves to a temp file and returns that path; copy the file into `$v/`.
6. **Report.** List `$v/` first and cite only proof files it lists. Write `$v/report.md`, below the stamp lines:
   - One line per item: Done-when item, pass or fail, proof path. Inconclusive is a fail, tests or browser.
   - Also, briefly: app started or restarted, **Health check** notes, values you set, any stale drive block you fixed.
   - Last, `.superflow/bin/proof.sh stamp <slug> after`; non-zero → start again from step 1.

Reply: the pass and fail counts and the report path.
