#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM_ID="${DEVELOPMENT_TEAM:-}"
PROFILE="${PROVISIONING_PROFILE_SPECIFIER:-}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE="$ROOT/build/UI16Phone.xcarchive"
EXPORT="$ROOT/build/export"

rm -rf "$ROOT/build"
mkdir -p "$ROOT/build"

echo "== UI16 Control / iPhone IPA =="
echo "Bundle: com.marqueslab.ui16control"
echo "Configuration: $CONFIGURATION"

XCODE_ARGS=(
  -scheme UI16Phone
  -packagePath "$ROOT"
  -configuration "$CONFIGURATION"
  -destination 'generic/platform=iOS'
  -archivePath "$ARCHIVE"
  -allowProvisioningUpdates
)

if [[ -n "$TEAM_ID" ]]; then XCODE_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic); fi
if [[ -n "$PROFILE" ]]; then XCODE_ARGS+=(PROVISIONING_PROFILE_SPECIFIER="$PROFILE" CODE_SIGN_STYLE=Manual); fi

xcodebuild archive "${XCODE_ARGS[@]}"

cat > "$ROOT/build/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>development</string>
<key>signingStyle</key><string>${PROFILE:+manual}${PROFILE:-automatic}</string>
<key>destination</key><string>export</string>
${TEAM_ID:+<key>teamID</key><string>$TEAM_ID</string>}
<key>provisioningProfiles</key><dict><key>com.marqueslab.ui16control</key><string>${PROFILE}</string></dict>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$ROOT/build/ExportOptions.plist" -allowProvisioningUpdates

IPA="$(find "$EXPORT" -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "$IPA" ]]; then echo 'IPA não foi gerado.'; exit 1; fi
cp "$IPA" "$ROOT/build/UI16-Control.ipa"
echo "IPA GERADO: $ROOT/build/UI16-Control.ipa"
