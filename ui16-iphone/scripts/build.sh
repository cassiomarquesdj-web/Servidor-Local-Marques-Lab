#!/bin/bash
# Compile the iPhone app (unsigned) to catch build errors quickly.
#   bash scripts/build.sh            # simulator
#   bash scripts/build.sh device     # physical-device slice
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/app/UI16Control.xcodeproj"
TARGET="${1:-simulator}"

if [[ "$TARGET" == "device" ]]; then
  DEST='generic/platform=iOS'
  SDK=iphoneos
else
  DEST='generic/platform=iOS Simulator'
  SDK=iphonesimulator
fi

echo "== UI16 Control — build ($TARGET) =="
xcodebuild \
  -project "$PROJECT" \
  -scheme UI16Control \
  -configuration "${CONFIGURATION:-Debug}" \
  -sdk "$SDK" \
  -destination "$DEST" \
  CODE_SIGNING_ALLOWED=NO \
  build
