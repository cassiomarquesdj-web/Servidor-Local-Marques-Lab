#!/bin/bash
# Build a signed .ipa of UI16 Control for a physical iPhone.
#
#   DEVELOPMENT_TEAM=ABCDE12345 bash scripts/build-ipa.sh
#
# Manual signing (when you want a specific profile):
#   DEVELOPMENT_TEAM=ABCDE12345 PROVISIONING_PROFILE_SPECIFIER="My Profile" bash scripts/build-ipa.sh
#
# Output: build/UI16-Control.ipa
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/app/UI16Control.xcodeproj"
SCHEME="UI16Control"
BUNDLE_ID="com.marqueslab.ui16control"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${DEVELOPMENT_TEAM:-}"
PROFILE="${PROVISIONING_PROFILE_SPECIFIER:-}"
EXPORT_METHOD="${EXPORT_METHOD:-development}"

ARCHIVE="$ROOT/build/UI16Control.xcarchive"
EXPORT_DIR="$ROOT/build/export"

echo "== UI16 Control — IPA =="
echo "   projeto : $PROJECT"
echo "   bundle  : $BUNDLE_ID"
echo "   config  : $CONFIGURATION"

if [[ -z "$TEAM_ID" ]]; then
  cat >&2 <<'MSG'

ERRO: defina DEVELOPMENT_TEAM com o seu Apple Team ID.

Como descobrir o Team ID:
  - Xcode > Settings > Accounts > selecione sua conta > o Team ID aparece na lista, ou
  - https://developer.apple.com/account  (Membership details)

Exemplo:
  DEVELOPMENT_TEAM=ABCDE12345 bash scripts/build-ipa.sh
MSG
  exit 1
fi

rm -rf "$ROOT/build"
mkdir -p "$ROOT/build"

args=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination 'generic/platform=iOS'
  -archivePath "$ARCHIVE"
  DEVELOPMENT_TEAM="$TEAM_ID"
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"
)

if [[ -n "$PROFILE" ]]; then
  args+=(CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER="$PROFILE")
  SIGNING_STYLE=manual
else
  args+=(CODE_SIGN_STYLE=Automatic)
  SIGNING_STYLE=automatic
fi

echo "== 1/2 Archive =="
xcodebuild archive "${args[@]}" -allowProvisioningUpdates

echo "== 2/2 Export IPA =="
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  echo '<plist version="1.0"><dict>'
  echo "<key>method</key><string>$EXPORT_METHOD</string>"
  echo "<key>signingStyle</key><string>$SIGNING_STYLE</string>"
  echo "<key>teamID</key><string>$TEAM_ID</string>"
  echo '<key>destination</key><string>export</string>'
  echo '<key>stripSwiftSymbols</key><true/>'
  echo '<key>compileBitcode</key><false/>'
  if [[ -n "$PROFILE" ]]; then
    echo '<key>provisioningProfiles</key><dict>'
    echo "<key>$BUNDLE_ID</key><string>$PROFILE</string>"
    echo '</dict>'
  fi
  echo '</dict></plist>'
} > "$ROOT/build/ExportOptions.plist"

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$ROOT/build/ExportOptions.plist" \
  -allowProvisioningUpdates

IPA="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "$IPA" ]]; then
  echo "ERRO: nenhum .ipa foi gerado em $EXPORT_DIR" >&2
  exit 1
fi

cp "$IPA" "$ROOT/build/UI16-Control.ipa"
echo
echo "IPA GERADO: $ROOT/build/UI16-Control.ipa"
echo "Instale no iPhone com Xcode (Window > Devices and Simulators) ou Apple Configurator."
