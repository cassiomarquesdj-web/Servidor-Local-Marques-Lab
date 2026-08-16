#!/bin/bash
# Create a device archive. Signed when DEVELOPMENT_TEAM is set, unsigned otherwise
# (an unsigned archive is useful to verify the build without an Apple account).
#   DEVELOPMENT_TEAM=ABCDE12345 bash scripts/archive.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/app/UI16Control.xcodeproj"
ARCHIVE="$ROOT/build/UI16Control.xcarchive"
TEAM_ID="${DEVELOPMENT_TEAM:-}"

mkdir -p "$ROOT/build"
args=(
  -project "$PROJECT"
  -scheme UI16Control
  -configuration "${CONFIGURATION:-Release}"
  -destination 'generic/platform=iOS'
  -archivePath "$ARCHIVE"
)

if [[ -n "$TEAM_ID" ]]; then
  echo "== Archive assinado (team $TEAM_ID) =="
  args+=(DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic)
  xcodebuild archive "${args[@]}" -allowProvisioningUpdates
else
  echo "== Archive SEM assinatura (defina DEVELOPMENT_TEAM para assinar) =="
  args+=(CODE_SIGNING_ALLOWED=NO)
  xcodebuild archive "${args[@]}"
fi

echo "ARCHIVE: $ARCHIVE"
