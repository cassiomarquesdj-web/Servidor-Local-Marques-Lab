#!/bin/bash
# Verifies that every Apple credential required for a *distributable* build is
# present. Exits non-zero with an explicit list of the missing GitHub Secrets.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MISSING=()

require() {
  local name="$1" purpose="$2"
  if [ -z "${!name:-}" ]; then
    MISSING+=("$name — $purpose")
  else
    ok "$name presente"
  fi
}

log "Verificando credenciais Apple para distribuição pública"
require APPLE_CERTIFICATE_BASE64  "certificado Developer ID Application (.p12) em base64"
require APPLE_CERTIFICATE_PASSWORD "senha usada ao exportar o .p12"
require APPLE_TEAM_ID             "Team ID de 10 caracteres da conta Apple Developer"

NOTARY_OK=0
if [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER_ID:-}" ] && [ -n "${APPLE_API_KEY_BASE64:-}" ]; then
  ok "Notarização via App Store Connect API key"
  NOTARY_OK=1
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
  ok "Notarização via Apple ID + senha específica de app"
  NOTARY_OK=1
fi
if [ "$NOTARY_OK" -ne 1 ]; then
  MISSING+=("APPLE_ID + APPLE_APP_PASSWORD (ou APPLE_API_KEY_ID + APPLE_API_ISSUER_ID + APPLE_API_KEY_BASE64) — credenciais de notarização")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  echo
  printf '\033[1;31m✗ BUILD DE DISTRIBUIÇÃO BLOQUEADO — credenciais Apple ausentes\033[0m\n'
  echo
  echo "Configure os seguintes GitHub Secrets no repositório"
  echo "(Settings → Secrets and variables → Actions → New repository secret):"
  echo
  for item in "${MISSING[@]}"; do
    echo "  • $item"
  done
  echo
  echo "Passo a passo completo: marqueslab-4k-download/DISTRIBUICAO.md"
  echo
  echo "Nenhum build ad-hoc/não assinado será publicado como release."
  exit 78
fi

log "Todas as credenciais Apple necessárias estão presentes."
