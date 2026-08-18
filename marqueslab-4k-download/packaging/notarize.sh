#!/bin/bash
# Submits an artifact to Apple notarization, waits for the verdict and staples
# the ticket. Usage: notarize.sh <path-to-.app|.dmg|.zip>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TARGET="${1:-}"
[ -n "$TARGET" ] || die "uso: notarize.sh <caminho>"
[ -e "$TARGET" ] || die "Artefato inexistente: $TARGET"

"$PKG_DIR/check_apple_credentials.sh" >/dev/null

WORK_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
NOTARY_ARGS=()
API_KEY_FILE=""

cleanup() { [ -n "$API_KEY_FILE" ] && rm -f "$API_KEY_FILE"; }
trap cleanup EXIT

if [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER_ID:-}" ] && [ -n "${APPLE_API_KEY_BASE64:-}" ]; then
  API_KEY_FILE="$WORK_DIR/AuthKey_${APPLE_API_KEY_ID}.p8"
  printf '%s' "$APPLE_API_KEY_BASE64" | base64 --decode > "$API_KEY_FILE"
  NOTARY_ARGS=(--key "$API_KEY_FILE" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
  log "Notarizando com App Store Connect API key"
else
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  log "Notarizando com Apple ID $APPLE_ID (Team $APPLE_TEAM_ID)"
fi

SUBMISSION="$TARGET"
if [ -d "$TARGET" ]; then
  SUBMISSION="$WORK_DIR/$(basename "$TARGET").zip"
  rm -f "$SUBMISSION"
  log "Compactando bundle para envio"
  ditto -c -k --keepParent "$TARGET" "$SUBMISSION"
fi

log "Enviando $(basename "$SUBMISSION") para a Apple (pode levar alguns minutos)"
set +e
SUBMIT_OUTPUT="$(xcrun notarytool submit "$SUBMISSION" "${NOTARY_ARGS[@]}" --wait --timeout 45m --output-format json 2>&1)"
SUBMIT_STATUS=$?
set -e
echo "$SUBMIT_OUTPUT"

REQUEST_ID="$("$PYTHON_BIN" - "$SUBMIT_OUTPUT" <<'PY'
import json, sys
try:
    print(json.loads(sys.argv[1]).get("id", ""))
except Exception:
    print("")
PY
)"
STATUS="$("$PYTHON_BIN" - "$SUBMIT_OUTPUT" <<'PY'
import json, sys
try:
    print(json.loads(sys.argv[1]).get("status", ""))
except Exception:
    print("")
PY
)"

if [ "$STATUS" != "Accepted" ] || [ $SUBMIT_STATUS -ne 0 ]; then
  warn "Notarização não aceita (status: ${STATUS:-desconhecido}). Log da Apple:"
  [ -n "$REQUEST_ID" ] && xcrun notarytool log "$REQUEST_ID" "${NOTARY_ARGS[@]}" || true
  die "Notarização rejeitada pela Apple"
fi
ok "Notarização aceita (id $REQUEST_ID)"

log "Aplicando o staple do ticket"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
ok "Ticket de notarização anexado a $(basename "$TARGET")"
