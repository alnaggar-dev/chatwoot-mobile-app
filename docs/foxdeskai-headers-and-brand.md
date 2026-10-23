# FoxDesk Ai client headers and brand

Every request through `apiService` tells the FoxDesk server which app sent it, using `X-Foxdeskai-*` headers. The server (FoxDesk server PR #63) reads client details only from these names, so the app no longer sends the upstream `X-Chatwoot-*` headers. The same change finishes the "FoxDesk Ai" brand in the copy users see and deletes the unused Chatwoot logo. Registered as `foxdesk-rebrand` in [`.fork/CHANGES.md`](../.fork/CHANGES.md).

- **Client headers**: the five `X-Foxdeskai-*` headers plus the `User-Agent` that `deviceHeaders()` builds once.
- **FoxDesk Ai**: the brand spelling, with a capital D and "Ai" (not "AI").

## Key files

| Path | Role |
| --- | --- |
| [`src/services/APIService.ts`](../src/services/APIService.ts) | `deviceHeaders()` builds the client headers; the `APIService` constructor merges them into `this.api.defaults.headers.common` |
| [`src/services/specs/APIService.spec.ts`](../src/services/specs/APIService.spec.ts) | Sends a request through `apiService` with a stub axios adapter and checks the headers on the wire |
| [`src/i18n/en.json`](../src/i18n/en.json), [`src/i18n/ar.json`](../src/i18n/ar.json) | Captain AI consent sheet text (`PURPOSE`) names "FoxDesk Ai" |
| [`src/screens/settings/components/DebugActions.tsx`](../src/screens/settings/components/DebugActions.tsx) | Settings debug list label "FoxDesk Ai Version" (hard-coded English, not an i18n string) |

## Constants and persisted contract

| Constant / field | Value | Source |
| --- | --- | --- |
| `CLIENT_NAME` | `'FoxDesk Ai Mobile'` | [`src/services/APIService.ts`](../src/services/APIService.ts) |
| `CLIENT_VERSION` | `Constants.expoConfig?.version ?? 'unknown'` | [`src/services/APIService.ts`](../src/services/APIService.ts) |
| `X-Foxdeskai-Client-Name` | `CLIENT_NAME` | `deviceHeaders()` |
| `X-Foxdeskai-Client-Version` | `CLIENT_VERSION` | `deviceHeaders()` |
| `X-Foxdeskai-Platform` | `Platform.OS` | `deviceHeaders()` |
| `X-Foxdeskai-Platform-Version` | `String(Device.osVersion ?? Platform.Version)` | `deviceHeaders()` |
| `X-Foxdeskai-Device-Model` | `Device.modelName ?? 'Unknown'` | `deviceHeaders()` |
| `User-Agent` | `` `${CLIENT_NAME}/${CLIENT_VERSION} (${platform} ${osVersion}; ${model})` `` | `deviceHeaders()` |

## How the headers reach the server

```text
APIService.getInstance()  (first call only)
  └─ constructor
       └─ Object.assign(api.defaults.headers.common, deviceHeaders())
            └─ every apiService.get/post/... request
                 ├─ X-Foxdeskai-* (5 headers)
                 ├─ User-Agent: FoxDesk Ai Mobile/<version> (<platform> <os>; <model>)
                 └─ auth headers added by the request interceptor
```

1. `deviceHeaders()` runs once, when `APIService` is first built.
2. The axios defaults carry the headers on every `apiService` request; callers change nothing.

## What it does / does NOT do
- Can: send the five `X-Foxdeskai-*` client headers on every `apiService` request; show "FoxDesk Ai" on the Captain AI consent sheet (English and Arabic) and in the Settings debug list.
- Does NOT: send any `X-Chatwoot-*` header.
- Does NOT: change the `User-Agent`. The server matches it to recognize old app versions.
- Does NOT: add client headers to the two plain-axios calls (`settingsService.getFoxDeskVersion`, analytics). They never sent `X-Chatwoot-*`, so adding headers there would be new behavior.
- Header spelling follows the server: `X-Foxdeskai-…`. HTTP header names ignore case, so `X-foxdeskai-…` is the same on the wire; it was rejected only because it differs from the server's spelling.
- Brand spelling is "FoxDesk Ai", as the app already writes it. "Foxdesk Ai" was rejected: it would change the app name and every other place the brand appears.
- The unused Chatwoot logo `src/assets/local/logo.png` is deleted, not replaced: no code used it.
- Keeps these Chatwoot names on purpose ([ADR 0001](adr/0001-keep-chatwoot-names-that-outside-systems-need.md)): the MIT license notice in `LICENSE` and `README`, the `@chatwoot/*` npm packages, the `chatwoot-dashboard-app:fetch-info` message, the iOS pod `chatwoot-ffmpeg-kit-ios-https`, and the upstream PR links in a `ReplyBoxContainer.tsx` comment.
- Keeps code names that say "FoxDesk" without "Ai" (`FoxDeskIcon`, `selectFoxDeskVersion`, `@foxdesk/…` storage keys, `EXPO_PUBLIC_FOXDESK_*`, and others) and the Android package id `com.foxdesk.app`. Users never see the code names; renaming the storage keys loses saved data; changing the package id makes a new Play Store app.
- Keeps the bot avatar `src/assets/local/bot-avatar.png`: a generic robot icon, not the Chatwoot name or logo.

## Verification map
The `foxdesk-rebrand` entry's Verify and Check live in [`.fork/CHANGES.md`](../.fork/CHANGES.md).

| Test path | Coverage |
| --- | --- |
| `src/services/specs/APIService.spec.ts` | The five `X-Foxdeskai-*` headers carry the device values, no other `X-` header is sent, and the `User-Agent` is unchanged. `APIService.ts` is upstream-owned, so this spec catches an upstream port that brings `X-Chatwoot-*` back. |

### Browser journey: brand copy on the iOS simulator
- **Reach**: a dev-client build (`pnpm ios`); signed in to a FoxDesk Ai account.
- **Setup**: none. The operator signs in on the simulator.
- **Steps**: open the Captain AI consent sheet; then Settings, scroll to the debug list. Repeat with the app language set to Arabic, then set it back to English.
- **Finished result**: the consent sheet says "FoxDesk Ai sends this data to OpenAI …" (English) and "يرسل FoxDesk Ai هذه البيانات …" (Arabic); the debug list labels the server version "FoxDesk Ai Version" in both layouts.
