# Keep the Chatwoot and old FoxDesk names that outside systems or the license need

The app ships as FoxDesk Ai, and the rebrand removes the Chatwoot name everywhere users see it. Some names stay on purpose, because something outside this repository depends on the exact string:

- The MIT notice in `LICENSE` ("Portions Copyright (c) 2017-2025 Chatwoot Inc.") and the README line "Based on the Chatwoot mobile app": the MIT license requires the fork to keep it.
- The npm packages `@chatwoot/markdown-to-txt`, `@chatwoot/react-native-widget` and `@chatwoot/utils`: these are registry names; renaming them means publishing the fork's own copies.
- The `chatwoot-dashboard-app:fetch-info` message in `DashboardScreen.tsx`: dashboard apps send this exact string; renaming it stops them from getting conversation data.
- The iOS pod `chatwoot-ffmpeg-kit-ios-https` (`with-ffmpeg-pod.js`, `patches/ffmpeg-kit-react-native.patch`): a published pod at that URL; renaming it breaks the iOS build.
- The Android package id `com.foxdesk.app`: the Play Store identity; changing it makes a new app.
- The `@foxdesk/…` storage keys: renaming them loses users' saved data.

## Rejected
- Rename everything to FoxDesk Ai: breaks the license terms, the build, dashboard apps or saved data, for names users never see.
