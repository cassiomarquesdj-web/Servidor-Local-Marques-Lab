#!/bin/bash
# Builds the distributable DMG: app + Applications shortcut, volume icon,
# compressed read-only image, signed with the same Developer ID.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[ -d "$APP_BUNDLE" ] || die "Bundle não encontrado: $APP_BUNDLE"

VOLUME_NAME="$APP_NAME"
STAGING="$PROJECT_DIR/build/dmg-staging"
TEMP_DMG="$PROJECT_DIR/build/temp.dmg"
MOUNT_POINT="$PROJECT_DIR/build/dmg-mount"

mkdir -p "$(dirname "$DMG_PATH")"
rm -rf "$STAGING" "$TEMP_DMG" "$MOUNT_POINT" "$DMG_PATH"
mkdir -p "$STAGING"

log "Montando o conteúdo do DMG"
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
if [ -f "$PROJECT_DIR/assets/AppIcon.icns" ]; then
  cp "$PROJECT_DIR/assets/AppIcon.icns" "$STAGING/.VolumeIcon.icns"
fi
ok "App + atalho para /Applications preparados"

log "Criando imagem de trabalho"
hdiutil create -srcfolder "$STAGING" -volname "$VOLUME_NAME" -fs HFS+ \
  -format UDRW -ov "$TEMP_DMG" >/dev/null

mkdir -p "$MOUNT_POINT"
hdiutil attach "$TEMP_DMG" -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
if [ -f "$MOUNT_POINT/.VolumeIcon.icns" ] && command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$MOUNT_POINT" && ok "Ícone de volume aplicado"
fi
sync
hdiutil detach "$MOUNT_POINT" >/dev/null
rmdir "$MOUNT_POINT" 2>/dev/null || true

log "Comprimindo a imagem final"
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$TEMP_DMG"
rm -rf "$STAGING"

if [ -n "${APPLE_SIGNING_IDENTITY_RESOLVED:-}" ]; then
  IDENTITY="$APPLE_SIGNING_IDENTITY_RESOLVED"
elif [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
  IDENTITY="$APPLE_SIGNING_IDENTITY"
else
  IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
if [ -n "$IDENTITY" ]; then
  log "Assinando o DMG com $IDENTITY"
  codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
  ok "DMG assinado"
else
  warn "Nenhuma identidade Developer ID disponível — DMG não assinado (build de engenharia)"
fi

log "Verificando a imagem"
hdiutil verify "$DMG_PATH" >/dev/null
ok "DMG pronto: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
echo "$DMG_PATH"
