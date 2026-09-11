---
name: release
description: Release the committed changes on custom/main to Google Play and the App Store end to end — bump the version when a store needs it, build both platforms on EAS, upload the builds, then finish the Play Console and App Store Connect submissions in the connected Chrome. Use when the user says "release", "ship it", "publish the update", "push to the stores", or runs /release.
---

# Release FoxDesk Ai to both stores

You are releasing whatever is committed on `custom/main` right now. The user running this
skill is the explicit go-ahead to submit for review in BOTH stores. Do not stop to ask
"shall I submit?". Stop only when genuinely blocked: uncommitted changes, EAS not logged in,
a build that fails, or a console that is not signed in. Never type passwords or codes.

Arguments (all optional, from `$ARGUMENTS`):
- A version like `4.8.0` forces that marketing version.
- `--notes "text"` sets the release note for both stores.
- `--skip-build <ios-build-id> <android-build-id>` reuses finished EAS builds.

## Fixed facts about this project

- Expo + EAS. `eas.json` has `appVersionSource: remote` and the production profile has
  `autoIncrement: true`, so **EAS bumps the build numbers by itself** (Android versionCode,
  iOS buildNumber) the moment a build starts. Never edit build numbers by hand.
- The marketing version lives in two files that must match: `version: 'X.Y.Z'` in
  `app.config.ts` and `"version": "X.Y.Z"` in `package.json`.
- EAS CLI is not installed globally. Always run `npx --yes eas-cli@latest …` and drop the
  `npm warn` lines. Expected account: foxdeskais-team.
- `eas submit` needs `.env` (EXPO_APPLE_ID etc.). The helper scripts source it for you.
- App Store Connect: app id 6760915913, bundle `com.foxdeskai.app`.
  Version page: https://appstoreconnect.apple.com/apps/6760915913/distribution
  TestFlight builds: https://appstoreconnect.apple.com/apps/6760915913/testflight/ios
- Play Console: developer account "Gulf Stock" id 5799523824211041526, app FoxDesk Ai
  id 4973184871205930223, package `com.foxdesk.app`.
  Base: https://play.google.com/console/u/0/developers/5799523824211041526/app/4973184871205930223/
  Production: base + `tracks/production` (add `?tab=releases` to list releases)
  Publishing overview: base + `publishing`
- `eas submit -p android` lands on the **internal** track (from `eas.json`). Production is
  reached in the console. Managed publishing is OFF, so an approved production release goes
  live on its own.
- Helper scripts, run from the repo root:
  - `.claude/skills/release/scripts/eas-status.sh` — preflight: git state, login, versions,
    last finished builds and the commits since each one.
  - `.claude/skills/release/scripts/wait-for-builds.sh <id>...` — polls ~9 min; exit 0 done,
    1 failed, 2 still running (run it again).
  - `.claude/skills/release/scripts/submit.sh ios|android <id>` — uploads a finished build.
  - `.claude/skills/release/scripts/download-aab.sh <id>` — fallback, saves the bundle to
    ~/Downloads for a manual drag-and-drop.

## Timing

Builds take about 10 minutes (both run in parallel). Apple processing takes 5 to 15 minutes
after upload. A full release is 30 to 45 minutes. Run anything longer than a minute as a
background Bash task (`run_in_background: true`, timeout 600000) and keep working on the
other store while it runs. Bash calls die at 10 minutes, so the pollers self-limit.

## Phase 0 — Preflight (run these in parallel)

1. Bash: `.claude/skills/release/scripts/eas-status.sh`. Requirements: branch `custom/main`,
   `uncommitted files: 0`, a logged-in account. Otherwise stop and tell the user what to fix.
   The "commits since last build" lists are exactly what ships. Turn them into the release
   note if `--notes` was not given: one or two plain sentences for end users, no commit
   jargon. Example: "Fixed the language switcher: changing the app language now applies once
   and no longer reloads the app several times."
2. Load the Chrome tools in ONE call:
   `ToolSearch select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__find,mcp__claude-in-chrome__form_input,mcp__claude-in-chrome__get_page_text,mcp__claude-in-chrome__browser_batch,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__tabs_close_mcp`
3. Open the consoles. Call `navigate` standalone (no tabId) with the App Store Connect
   version page; that creates the tab group and returns the tab id. Then `tabs_create_mcp`
   and `navigate` the new tab to the Play Console production URL. Wait 5 to 7 seconds after
   each navigate before reading the page.
   - Play Console may show "Choose developer account": `read_page filter interactive`, click
     the "Gulf Stock" option by ref.
   - If either site shows a sign-in form, stop and ask the user to sign in in Chrome, then
     continue from here.

## Phase 1 — Decide the version

Read `V` from `app.config.ts`. Look at the App Store Connect sidebar under "iOS App":

- `V` shows "Ready for Distribution", "Ready for Sale", "Pending Developer Release",
  "Waiting for Review" or "In Review" → Apple will not accept another build of `V`.
  Bump the patch number (`4.7.1` → `4.7.2`) unless the user passed a version.
- `V` shows "Prepare for Submission", "Rejected" or "Developer Rejected" → reuse `V`; the
  version already exists in App Store Connect, so skip the "+" step in Phase 3a.
- `V` is not listed at all → reuse `V` and create it in Phase 3a.

Google Play only needs a higher versionCode, which EAS provides, so the version name follows.

If bumping, do it now so the builds carry the new number:

```bash
sed -i '' "s/version: 'OLD'/version: 'NEW'/" app.config.ts && sed -i '' 's/"version": "OLD"/"version": "NEW"/' package.json && git add app.config.ts package.json && git commit -q -m "chore: bump version to NEW" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

Do not push. Tell the user at the end that the commit is local.

## Phase 2 — Build both platforms (background)

Skip when `--skip-build` was given.

```bash
npx --yes eas-cli@latest build -p all --profile production --non-interactive --no-wait 2>&1 | grep -v "npm warn"
```

Read from its output: the "Incremented versionCode from A to B" and "Incremented buildNumber
from C to D" lines (B and D are the new build numbers) and the two build ids at the end of the
"See 🤖 Android logs" and "See 🍏 iOS logs" URLs. Then start the poller in the background:

```bash
.claude/skills/release/scripts/wait-for-builds.sh <ios-id> <android-id>
```

Exit 2 means run it again. Exit 1 means a build failed: open its expo.dev URL, read the log
tail, report the error, and stop. While it runs, do Phase 3a.

## Phase 3a — App Store Connect: prepare the version (while building)

On the App Store Connect tab:

1. Only if a new version is needed: `find "plus button next to iOS App to add a version"`
   and click it by ref (it sits right of the "iOS App" label in the sidebar). In the
   "New Version" dialog click the Version field, type the version, click Create. The sidebar
   should now show "X.Y.Z Prepare for Submission".
2. `find "What's New in This Version text area"` → `scroll_to` → click → type the release note.
3. `find "Save button at top of version page"` → `scroll_to` → click by ref. The Save button
   shows a check mark when saved.
4. Touch nothing else on the page.

## Phase 3b — Upload the iOS build

As soon as the poller reports `IOS:FINISHED`, run in the background:

```bash
.claude/skills/release/scripts/submit.sh ios <ios-id>
```

Success line: "Submitted your app to Apple App Store Connect!". Apple then processes the
build. Start a background `sleep 360` as a timer and do Phase 4 meanwhile.

## Phase 3c — Attach the build and submit for review

1. `navigate` the App Store Connect tab to
   `https://appstoreconnect.apple.com/apps/6760915913/distribution/ios/version/inflight`,
   wait 6 seconds.
2. `find "Build section heading or Add Build button"` → `scroll_to` the heading → click
   "Add Build" by ref. A dialog lists processed builds.
   - If the new build is not listed, it is still processing. Check the TestFlight URL
     ("Processing" vs "Complete"), wait 3 to 5 minutes, retry. There is no export-compliance
     question (`ITSAppUsesNonExemptEncryption` is false).
3. `find "build X.Y.Z (N) row or its radio button in the Add Build dialog"` → click the radio
   by ref → `find "Done button in the Add Build dialog"` → click by ref. Coordinate clicks do
   NOT land on this modal; always use the ref.
4. `find "Save button at top of version page"` → click. Then `scroll_to` the Build heading and
   confirm the table shows the new build number and version.
5. `find "Add for Review button"` → click by ref. A "Draft Submissions" panel opens with
   "iOS App X.Y.Z (N)". Wait for its spinner, then `find "Submit for Review button"` → click
   by ref. Expect "1 Item Submitted". iOS is done.

## Phase 4 — Google Play

1. When the poller reports `ANDROID:FINISHED`, run in the background:

   ```bash
   .claude/skills/release/scripts/submit.sh android <android-id>
   ```

   It lands on the Internal testing track.
   - If it fails with a credentials or permission error: run
     `.claude/skills/release/scripts/download-aab.sh <android-id>`, open Production →
     "Create new release" in the Play tab, and ask the user to drag the file from ~/Downloads
     into the "Drop app bundles here" box. Do NOT try `file_upload` (10 MB cap) and do NOT
     script the upload with `javascript_tool`. Continue at step 3 once the bundle row appears.
2. Put the bundle in a Production release. On the Play tab, `navigate` to the Production
   URL, wait, `find "Create new release button"` → click by ref. On the "Create production
   release" page, `find "Add from library button"` → click, pick the row with the new
   version code, confirm. (Alternative that reaches the same page: Testing → Internal
   testing → the new release → "Promote release" → Production.)
3. Release notes: `find "Release notes textbox with en-US tags"` and set it with
   `form_input` to exactly:

   ```
   <en-US>
   YOUR RELEASE NOTE
   </en-US>
   ```

   The page then says "Release notes provided for 1 language". The release name fills itself.
4. Click "Next" (bottom right). The "Preview and confirm" page should say "Ready to release".
   Scroll through it for errors, then `find "Save button"` → click by ref. In the
   "Go to Publishing overview?" dialog click "Go to overview".
5. On Publishing overview: `find "Send changes for review button"` → click ("Submit 1 change
   for review"). In the "Send 1 change for review?" dialog `find "confirm Submit button in the
   dialog"` → click "Send changes for review". The page switches to "Changes in review".
   Google's quick checks run up to 14 minutes and then send it on automatically.
6. Verify: `navigate` to Production + `?tab=releases`; the new release shows "In review".

## Phase 5 — Report

Give the user a short table: Store | Version | Build | Status. Say that the version-bump
commit is local and needs `git push origin custom/main`. Leave both console tabs open so
the user can look.

## Browser gotchas learned the hard way

- Play Console needs 5 to 7 seconds after `navigate` before `find` sees the content. If `find`
  says the section "is not in the accessibility tree", wait 4 seconds and retry once.
- Screenshots inside `browser_batch` on the Play Console sometimes come back "Image omitted
  due to error". Take a standalone `computer screenshot` instead. Use `scale: 0.6`.
- If the permission classifier blocks a `browser_batch` that contains a `navigate`, run the
  `navigate` standalone and continue with the rest.
- Click dialog buttons by `ref` from `find`, never by coordinates.
- `form_input` works for the Play release-notes textarea; typing works for the App Store
  "What's New" box.
- Never enter credentials, never use `javascript_tool` to push files into a page.
