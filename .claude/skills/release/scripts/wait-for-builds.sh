#!/usr/bin/env bash
# Usage: wait-for-builds.sh <eas-build-id>...
# Polls EAS every 35 s for about 9 minutes (fits one background Bash call).
# Exit 0 = all FINISHED. Exit 1 = a build ERRORED/CANCELED. Exit 2 = still running, run again.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
ids=("$@")
[ ${#ids[@]} -gt 0 ] || { echo "usage: $0 <build-id>..."; exit 64; }
for n in $(seq 1 11); do
  line=""; bad=0; running=0
  for id in "${ids[@]}"; do
    st=$(npx --yes eas-cli@latest build:view "$id" --json 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const b=JSON.parse(s);console.log(`${b.platform}:${b.status}:${b.appVersion}(${b.appBuildVersion})${b.error?" ERR="+b.error.message:""}`)})' 2>/dev/null)
    [ -n "$st" ] || st="$id:UNKNOWN"
    line="$line $st"
    case "$st" in
      *:FINISHED:*) ;;
      *:ERRORED*|*:CANCELED*) bad=1 ;;
      *) running=1 ;;
    esac
  done
  echo "$(date +%H:%M:%S)$line"
  [ $bad -eq 1 ] && { echo "FAILED"; exit 1; }
  [ $running -eq 0 ] && { echo "DONE"; exit 0; }
  sleep 35
done
echo "STILL_RUNNING (run again)"
exit 2
