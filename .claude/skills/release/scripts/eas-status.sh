#!/usr/bin/env bash
# Preflight for /release: git state, EAS login, app version, remote build numbers,
# last FINISHED production build per platform, and the commits since each one.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
EAS="npx --yes eas-cli@latest"

echo "== git =="
echo "branch: $(git rev-parse --abbrev-ref HEAD)  head: $(git rev-parse --short HEAD)"
dirty=$(git status --porcelain | wc -l | tr -d ' ')
echo "uncommitted files: $dirty"

echo "== eas whoami =="
$EAS whoami 2>&1 | grep -v "npm warn"

echo "== app version =="
echo "app.config.ts: $(grep -o "version: '[^']*'" app.config.ts)"
echo "package.json:  $(node -p "require('./package.json').version")"

echo "== remote build numbers (EAS auto-increments these at build start) =="
$EAS build:version:get -p all --profile production --non-interactive 2>&1 | grep -E "versionCode|buildNumber"

echo "== last finished production builds =="
$EAS build:list --limit 20 --non-interactive --json 2>/dev/null | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const a=JSON.parse(s).filter(b=>b.buildProfile==="production"&&b.status==="FINISHED");
  for(const p of ["IOS","ANDROID"]){const b=a.find(x=>x.platform===p);
    if(!b){console.log(`${p}: none`);continue;}
    console.log(`${p}: ${b.appVersion} (${b.appBuildVersion}) commit ${(b.gitCommitHash||"").slice(0,7)} ${b.createdAt.slice(0,16)} id ${b.id}`);
    console.log(`${p}_SHA=${b.gitCommitHash||""}`);}
});' | tee /tmp/eas-status.$$ | grep -v "_SHA="

for p in IOS ANDROID; do
  sha=$(grep "^${p}_SHA=" /tmp/eas-status.$$ | cut -d= -f2)
  echo "== commits since last $p build =="
  if [ -n "$sha" ] && git cat-file -e "$sha" 2>/dev/null; then git log --oneline "$sha"..HEAD; else echo "(unknown base commit)"; fi
done
rm -f /tmp/eas-status.$$
