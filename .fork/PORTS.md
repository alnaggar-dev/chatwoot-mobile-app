# Upstream Port Journal

Short memory for the next port, not a diary. `upstream-port` step 9 appends one entry per release merge, written by hand and committed on the port branch before the push; a port revert and a reapply get one too. Git's ancestry records which releases are in; this journal records why each decision went the way it did.

A release-merge entry, headed `## <date> — port upstream <tag> (<pointer>..<target>)`, records:

- Conflicts: each file and how it was resolved (rerere replays reviewed, the side taken, fork behavior carried onto upstream's redesign, what the operator decided).
- Let in: every file outside upstream's diff that step 7 allowed into the merge commit, and why.
- Ledger: a verdict per disturbed entry (HOLDS, fixed in `<sha>`, asked), entries updated for renames or unregistered files; retirement candidates.
- `agents-md:` one line per upstream `AGENTS.md` rule, `agents-md: adopted|rejected|covered — <rule in ≤12 words> — <why>`, or `agents-md: none`. Grep this file for earlier verdicts before judging a rule again.
- Deploy: what `ship` must know (the post-port step, silent-surface changes such as feature flags, env, config, runtime versions), or none.
- Follow-ups.

Step 1 greps for two lines, each written at the start of a line. A revert entry (`upstream-port revert`) carries `port-reverted: <revert sha>` with the tag and why; the port that reapplies it carries `port-reapplied: <revert sha>`, the same full SHA (step 1 matches the text). A `port-reverted` line with no later matching `port-reapplied` line means the next port reapplies that release first.

<!-- Example:
## 2026-10-14 — port upstream v2.3.0 (9f920b549c..4c1d2e3f5a)

Conflicts (3):
  - package-lock.json — upstream's side, regenerated with the Regenerate lockfiles command; the fork's pins survived
  - src/jobs/response_builder.ts — upstream split normalization into a helper; the fork's extra field now travels inside it (rich-replies)
  - schema.sql — upstream's side, regenerated with the Regenerate generated files command
Let in: none
Ledger: rich-replies HOLDS; login-banner fixed in 5e6f7a8b9c; retirement candidate: hide-build-info
agents-md: none
Deploy: one migration, adds an index; new optional env var RESPONSE_TIMEOUT
Follow-ups: none
-->

---

## 2026-10-04 — port upstream v4.8.0 (118facf80d..f5fef05cdf)

Conflicts (2):
  - app.config.ts — version line: upstream's 4.8.0 over the fork's 4.7.2; the fork's own release bumps follow upstream's numbering, and 4.8.0 is above 4.7.2 so store versions keep rising (the operator's question was cancelled; the agent decided)
  - package.json — the same version line, the same resolution; upstream's @chatwoot/utils ^0.0.33 → ^0.0.56 bump and pnpm-lock.yaml auto-merged, `pnpm install` found the lockfile up to date, the fork's pins unchanged
Let in: none
Ledger: foxdesk-rebrand, foxdesk-redesign, mobile-account-deletion, android-push-reliability, captain-ai-consent HOLD; rtl-and-arabic-locale fixed in 3221b68 (ar.json lost key parity: 18 WhatsApp template strings translated); no moved, missing or unregistered paths; retirement candidates: none
agents-md: none
Deploy: app version 4.8.0 (app.config.ts, package.json); @chatwoot/utils 0.0.56 is a JavaScript-only package, no native rebuild; post-port step `pnpm install`
Follow-ups:
  - done after the port: the WhatsApp templates sheet and the attachment menu's shared row label (CommandOptionsMenu.tsx) moved onto the foxdesk-redesign tokens, and the sheet got the rtl-text-alignment overrides (template inputs right-aligned under RTL, media-URL input kept LTR); rtl-and-arabic-locale's Verify now checks ar.json/en.json key parity
  - this port branch was cut from local custom/main, which held 3 unpushed commits (SuperFlow kit v5 and scripts/__pycache__/build-din-next-fonts.cpython-313.pyc); they land with this port, and the .pyc looks committed by accident
  - v4.9.0 contains 83b40a1 (#1130), upstream's own fix for rn79-back-handler: retire the entry inside the v4.9.0 port, not before it (fork-change RETIRE.md allows it only once the release is merged) — at the src/app.tsx conflict take upstream's subscription code and error boundary, keep the FoxDesk component name, and delete the entry in the same resolution

## 2026-10-23 — port upstream v4.9.0 (f5fef05cdf..c788437910)

Conflicts (7):
  - src/app.tsx — upstream's side (#1130 error boundary, #1111 BackHandler subscription.remove()); mergiraf kept the FoxDesk component name; rn79-back-handler retired in the same resolution (upstream supplies it; its Verify failed only on upstream's line wrapping)
  - src/screens/chat-screen/components/message-components/MarkdownDisplay.tsx — upstream deleted it with the old chat cells (#1117) and nothing imports it; the fork's DIN font hunks in it went with it; the path left din-next-font's Files and Tripwire paths
  - README.md — the fork's README kept; upstream's copyright year 2026 carried into the fork's attribution line
  - package.json — the fork's name @foxdesk/mobile-app with upstream's version 4.9.0 (the v4.8.0 rule); react-native-restart kept next to upstream's new reanimated, safe-area-context and screens versions
  - pnpm-lock.yaml — upstream's side, then `pnpm install` (CI=true makes pnpm frozen, so `--no-frozen-lockfile`); the only delta from upstream's lockfile is react-native-restart; the fork's pins survived
  - src/screens/settings/SettingsScreen.tsx — upstream moved every sheet onto its new Sheet component; the fork's CaptainConsentSheet, FOXDESK widget env vars and LiveChatWidget carried onto it, the consent ref typed SheetRef (ReplyBoxContainer.tsx, upstream's file, got the same ref type in the merge)
  - src/screens/conversations/components/conversation-header/ConversationHeaderPresenter.tsx — upstream replaced the left icons' entering/exiting swap with an opacity crossfade for Reanimated 4 (2a124df in #1111); the fork's large left-aligned title and trailing action cluster kept, and search, select-all and clear-filter now share one crossfading ActionSlot in that cluster (the active layer sizes the slot, inactive layers fade out absolutely at the end edge), fork tokens kept; the agent decided, no operator question
Let in:
  - .fork/CHANGES.md — ledger: rn79-back-handler retired, MarkdownDisplay.tsx dropped from din-next-font
  - src/i18n/ar.json — Arabic for upstream's three new ERRORS keys (the error boundary's copy); rtl-and-arabic-locale's key-parity Verify gates the port commit
Ledger: foxdesk-rebrand, foxdesk-redesign, pin-installation-url, mobile-account-deletion, android-push-reliability, rtl-and-arabic-locale, rtl-text-alignment, din-next-font HOLD; captain-ai-consent fixed in fcedadc6 (CaptainConsentSheet still rendered gorhom's BottomSheetModal, which throws without the provider upstream removed, so Settings and the reply box broke; now on Sheet with dismissible={false}, body scrolls past 85% of the screen; Verify, Depends on upstream, Tripwire paths and Must still be true updated); rn79-back-handler retired; no moved, missing or unregistered paths; retirement candidate: android-push-reliability's API 36 part (upstream now sets compileSdk/targetSdk 36 itself), the entry stays for token refresh, banners, notifee linking and press routing
agents-md: none
Deploy:
  - a native release, not an OTA update: Expo SDK 53 → 57, React Native 0.79 → 0.86 with the New Architecture on, React 19.2, Reanimated 4.5 with react-native-worklets 0.10, react-native-true-sheet in place of @gorhom/bottom-sheet; app version 4.9.0 (app.config.ts, package.json); needs a fresh EAS build for both stores
  - build config: splash moved into the expo-splash-screen plugin, Sentry plugin is now `@sentry/react-native`, iOS `useFrameworks: 'static'` removed, new config plugins with-notifee-maven-repo.js and with-ios-modular-headers.js, new pnpm patches (clipboard, menu, audio-recorder-player, react-native-modal, expo-modules-jsi); iOS floor is 15.1 (React Native 0.86)
  - Sentry: trace sampling 1.0 → 0.05, transport errors dropped, screenshots no longer attached
  - local dev: Expo 57's env loader refuses personal variables (JAVA_HOME) in `.env`; move them to `.env.local`
  - post-port step `pnpm install`
Follow-ups:
  - device QA, not done in the port (no native build ran): the Captain AI consent sheet from the Settings row and the reply-box AI button, on a small screen and in Arabic (body scrolls, buttons reachable, no swipe or tap-outside close); the conversation header crossfade between search, select-all and clear filter; the language switch restart (react-native-restart 0.0.27 is a legacy native module that now runs through the New Architecture interop layer; if it fails, expo's reloadAppAsync is the replacement)
  - found by the tripwire scouts, not caused by the port: a notification press that arrives before navigation is ready can be lost (AppTabs.tsx openNotification); ssoUtils.ts sends foxdeskaiapp://sso/callback while SSO_CALLBACK_URL is foxdeskaiapp://auth/saml; README.md claims iOS 13.4+ and Android 6.0+ while the floors are iOS 15.1 and Android 7.0
  - upstream's Sheet hardcodes cornerRadius 26 and bg-white, so the redesign's 20px sheet radius token does not reach sheet chrome (the gorhom sheets used 26px too)
