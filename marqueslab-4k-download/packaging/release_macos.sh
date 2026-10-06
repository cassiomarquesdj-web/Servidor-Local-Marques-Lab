#!/bin/bash
# End-to-end macOS release pipeline.
#   packaging/release_macos.sh
# Stops with an explicit message at the first step whose Apple credentials are
# missing. Never produces an ad-hoc "release".
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

log "Pipeline de release macOS — $APP_NAME $APP_VERSION (${ARCH_TAG})"

"$PKG_DIR/build_app.sh"
"$PKG_DIR/check_apple_credentials.sh"
"$PKG_DIR/sign_app.sh"
"$PKG_DIR/notarize.sh" "$APP_BUNDLE"
"$PKG_DIR/make_dmg.sh"
"$PKG_DIR/notarize.sh" "$DMG_PATH"
"$PKG_DIR/verify_release.sh" "$DMG_PATH"

log "Artefato final: $DMG_PATH"
