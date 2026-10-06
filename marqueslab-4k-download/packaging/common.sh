#!/bin/bash
# Shared helpers for the macOS release pipeline.
set -euo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$PKG_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

APP_NAME="$("$PYTHON_BIN" -c "import sys; sys.path.insert(0,'$PROJECT_DIR'); import branding; print(branding.APP_NAME)")"
APP_SLUG="$("$PYTHON_BIN" -c "import sys; sys.path.insert(0,'$PROJECT_DIR'); import branding; print(branding.APP_SLUG)")"
BUNDLE_ID="$("$PYTHON_BIN" -c "import sys; sys.path.insert(0,'$PROJECT_DIR'); import branding; print(branding.BUNDLE_ID)")"
APP_VERSION="$("$PYTHON_BIN" -c "import sys; sys.path.insert(0,'$PROJECT_DIR'); import branding; print(branding.VERSION)")"

ARCH_TAG="${MARQUESLAB_ARCH_TAG:-$(uname -m)}"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$PROJECT_DIR/release/${APP_SLUG}-${APP_VERSION}-${ARCH_TAG}.dmg"
ENTITLEMENTS="$PKG_DIR/entitlements.plist"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  ✗ %s\033[0m\n' "$*" >&2; exit 1; }
