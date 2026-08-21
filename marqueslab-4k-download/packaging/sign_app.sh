#!/bin/bash
# Imports the Developer ID Application certificate and signs the .app
# inside-out with the Hardened Runtime enabled.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[ -d "$APP_BUNDLE" ] || die "Bundle não encontrado: $APP_BUNDLE (rode build_app.sh antes)"
[ -f "$ENTITLEMENTS" ] || die "Entitlements não encontrados: $ENTITLEMENTS"

"$PKG_DIR/check_apple_credentials.sh"

KEYCHAIN_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN="$KEYCHAIN_DIR/marqueslab-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
CERT_FILE="$KEYCHAIN_DIR/developer_id.p12"

cleanup() {
  rm -f "$CERT_FILE"
}
trap cleanup EXIT

log "Importando certificado Developer ID Application"
printf '%s' "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$CERT_FILE"
[ -s "$CERT_FILE" ] || die "APPLE_CERTIFICATE_BASE64 não decodificou para um .p12 válido"

security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$CERT_FILE" -k "$KEYCHAIN" -P "$APPLE_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security -f pkcs12
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

IDENTITY="${APPLE_SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
[ -n "$IDENTITY" ] || die "Nenhuma identidade 'Developer ID Application' encontrada no certificado fornecido. Certificados 'Apple Development' ou 'Mac Developer' NÃO servem para distribuição fora da App Store."
case "$IDENTITY" in
  "Developer ID Application"*) ok "Identidade: $IDENTITY" ;;
  *) die "Identidade '$IDENTITY' não é um Developer ID Application. Exporte o certificado correto." ;;
esac

sign() {
  codesign --force --timestamp --options runtime \
    --keychain "$KEYCHAIN" --sign "$IDENTITY" "$@"
}

log "Removendo assinaturas ad-hoc anteriores e assinando binários internos"
COUNT=0
while IFS= read -r binary; do
  [ -n "$binary" ] || continue
  sign "$binary" >/dev/null 2>&1 || sign "$binary"
  COUNT=$((COUNT + 1))
done < <("$PYTHON_BIN" "$PKG_DIR/list_macho.py" "$APP_BUNDLE")
ok "$COUNT binários Mach-O assinados"

log "Assinando frameworks aninhados"
while IFS= read -r framework; do
  [ -n "$framework" ] || continue
  sign "$framework" >/dev/null
done < <(find "$APP_BUNDLE" -type d -name "*.framework" -depth)
ok "Frameworks assinados"

log "Assinando o bundle do aplicativo com entitlements de Hardened Runtime"
sign --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

log "Verificando a assinatura"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign --display --verbose=4 "$APP_BUNDLE" 2>&1 | tee "$KEYCHAIN_DIR/codesign-info.txt"

grep -q "Authority=Developer ID Application" "$KEYCHAIN_DIR/codesign-info.txt" \
  || die "O aplicativo não está assinado por um Developer ID Application"
grep -q "TeamIdentifier=$APPLE_TEAM_ID" "$KEYCHAIN_DIR/codesign-info.txt" \
  || die "TeamIdentifier não confere com APPLE_TEAM_ID"
codesign --display --entitlements - "$APP_BUNDLE" >/dev/null
if codesign --display --verbose=4 "$APP_BUNDLE" 2>&1 | grep -q "flags=.*runtime"; then
  ok "Hardened Runtime habilitado"
else
  die "Hardened Runtime NÃO está habilitado — a notarização seria rejeitada"
fi
ok "Assinatura Developer ID válida"
