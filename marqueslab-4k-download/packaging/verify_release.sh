#!/bin/bash
# Final release gate: nothing is publishable unless every check below passes on
# a machine that has never seen the developer certificate.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DMG="${1:-$DMG_PATH}"
[ -f "$DMG" ] || die "DMG não encontrado: $DMG"

FAILURES=0
check() {
  local label="$1"; shift
  if "$@" >/tmp/marqueslab-check.log 2>&1; then
    ok "$label"
  else
    printf '\033[1;31m  ✗ %s\033[0m\n' "$label"
    sed 's/^/      /' /tmp/marqueslab-check.log
    FAILURES=$((FAILURES + 1))
  fi
}

log "Validação final de distribuição — $(basename "$DMG")"

check "DMG íntegro (hdiutil verify)" hdiutil verify "$DMG"
check "DMG assinado (codesign --verify)" codesign --verify --verbose=2 "$DMG"
check "Ticket de notarização no DMG (stapler validate)" xcrun stapler validate "$DMG"

MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT

APP_IN_DMG="$MOUNT/$APP_NAME.app"
[ -d "$APP_IN_DMG" ] || die "O DMG não contém $APP_NAME.app"
[ -L "$MOUNT/Applications" ] || die "O DMG não contém o atalho para /Applications"
ok "DMG contém o aplicativo e o atalho para /Applications"

check "Assinatura do app (codesign --verify --deep --strict)" \
  codesign --verify --deep --strict --verbose=2 "$APP_IN_DMG"
check "Ticket de notarização no app (stapler validate)" xcrun stapler validate "$APP_IN_DMG"
check "Gatekeeper aceita a execução (spctl --assess)" \
  spctl --assess --type execute --verbose=4 "$APP_IN_DMG"

log "Detalhes da assinatura"
codesign --display --verbose=4 "$APP_IN_DMG" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier|flags' || true

if codesign --display --verbose=4 "$APP_IN_DMG" 2>&1 | grep -q "flags=.*runtime"; then
  ok "Hardened Runtime ativo"
else
  printf '\033[1;31m  ✗ Hardened Runtime ausente\033[0m\n'
  FAILURES=$((FAILURES + 1))
fi

if codesign --display --verbose=4 "$APP_IN_DMG" 2>&1 | grep -q "Authority=Developer ID Application"; then
  ok "Assinado por Developer ID Application"
else
  printf '\033[1;31m  ✗ Não assinado por Developer ID Application (build ad-hoc não é aceito)\033[0m\n'
  FAILURES=$((FAILURES + 1))
fi

log "Executando o aplicativo a partir do DMG (ambiente limpo)"
if "$APP_IN_DMG/Contents/MacOS/$APP_NAME" --self-test; then
  ok "Aplicativo inicia e resolve FFmpeg sem dependências externas"
else
  printf '\033[1;31m  ✗ O aplicativo não passou no self-test\033[0m\n'
  FAILURES=$((FAILURES + 1))
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  printf '\033[1;32m✓ RELEASE READY — assinatura, notarização, staple, Gatekeeper e execução validados\033[0m\n'
else
  die "$FAILURES verificação(ões) falharam — o build NÃO está pronto para release"
fi
