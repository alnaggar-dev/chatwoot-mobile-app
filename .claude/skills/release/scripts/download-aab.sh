#!/usr/bin/env bash
# Usage: download-aab.sh <android-eas-build-id>
# Fallback when `eas submit -p android` fails: saves the bundle to ~/Downloads so the
# user can drag it into the Play Console (browser tools cannot upload files > 10 MB).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
id="${1:?usage: download-aab.sh <android-build-id>}"
read -r url ver code < <(npx --yes eas-cli@latest build:view "$id" --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const b=JSON.parse(s);console.log(b.artifacts.applicationArchiveUrl,b.appVersion,b.appBuildVersion)})')
out="$HOME/Downloads/foxdesk-${ver}-${code}.aab"
curl -sL "$url" -o "$out"
ls -la "$out"
