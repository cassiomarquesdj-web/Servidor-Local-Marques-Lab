#!/bin/bash
# Builds the macOS .app with PyInstaller and validates the bundled FFmpeg.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cd "$PROJECT_DIR"

log "Construindo $APP_NAME $APP_VERSION (${MARQUESLAB_TARGET_ARCH:-nativo $ARCH_TAG})"
rm -rf build "$DIST_DIR"
"$PYTHON_BIN" -m PyInstaller --noconfirm --clean MarquesLab4KDownload.spec

[ -d "$APP_BUNDLE" ] || die "PyInstaller não gerou $APP_BUNDLE"
ok "Bundle criado: $APP_BUNDLE"

MAIN_BIN="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
[ -x "$MAIN_BIN" ] || die "Executável principal ausente em $MAIN_BIN"
log "Arquiteturas do executável principal"
lipo -info "$MAIN_BIN"

log "Validando FFmpeg embarcado"
BUNDLED_FFMPEG="$("$PYTHON_BIN" - "$APP_BUNDLE" <<'PY'
import sys
from pathlib import Path
app = Path(sys.argv[1])
for candidate in (
    app / "Contents/Frameworks/ffmpeg",
    app / "Contents/Resources/ffmpeg",
    app / "Contents/MacOS/ffmpeg",
):
    if candidate.is_file():
        print(candidate)
        break
else:
    sys.exit("FFmpeg não foi embarcado no bundle")
PY
)"
ok "FFmpeg embarcado: $BUNDLED_FFMPEG"
"$BUNDLED_FFMPEG" -version | head -n 1
lipo -info "$BUNDLED_FFMPEG"

log "Validando Info.plist"
PLIST="$APP_BUNDLE/Contents/Info.plist"
plutil -lint "$PLIST" >/dev/null || die "Info.plist inválido"
for key in CFBundleIdentifier CFBundleShortVersionString LSMinimumSystemVersion NSHighResolutionCapable; do
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST" 2>/dev/null || true)"
  [ -n "$value" ] || die "Info.plist sem a chave $key"
  ok "$key = $value"
done
[ -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ] || die "Ícone do aplicativo ausente no bundle"
ok "Ícone presente no bundle"

log "Conferindo o requisito mínimo de macOS declarado"
if ! "$PYTHON_BIN" "$PKG_DIR/check_deployment_target.py" "$APP_BUNDLE"; then
  if [ "${MARQUESLAB_ALLOW_HOST_PYTHON:-0}" = "1" ]; then
    warn "BUILD DE ENGENHARIA: o Python usado exige um macOS mais novo que o declarado."
    warn "Este bundle roda apenas nesta máquina e NÃO pode virar release."
  else
    die "LSMinimumSystemVersion incompatível com os binários embarcados. Use um Python com deployment target antigo (python.org / actions-setup-python) ou exporte MARQUESLAB_ALLOW_HOST_PYTHON=1 para um build local de engenharia."
  fi
fi

log "Smoke test do aplicativo empacotado"
if QT_QPA_PLATFORM=offscreen "$MAIN_BIN" --self-test; then
  ok "Aplicativo empacotado inicializa, importa a engine e executa o FFmpeg embarcado"
else
  TARGET="${MARQUESLAB_TARGET_ARCH:-$(uname -m)}"
  if [ "$TARGET" = "$(uname -m)" ] || [ "$TARGET" = "universal2" ]; then
    die "Smoke test falhou no bundle gerado"
  fi
  warn "Bundle $TARGET não é executável neste host ($(uname -m)) — smoke test adiado para a validação final"
fi
