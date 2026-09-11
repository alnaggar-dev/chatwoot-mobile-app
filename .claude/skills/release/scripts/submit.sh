#!/usr/bin/env bash
# Usage: submit.sh ios|android <eas-build-id>
# Uploads a finished EAS build: ios -> App Store Connect (TestFlight processing),
# android -> Google Play internal track (track comes from eas.json).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
p="${1:?usage: submit.sh ios|android <build-id>}"
id="${2:?usage: submit.sh ios|android <build-id>}"
set -a; . ./.env; set +a
npx --yes eas-cli@latest submit -p "$p" --profile production --id "$id" --non-interactive 2>&1 | grep -v "npm warn"
exit "${PIPESTATUS[0]}"
