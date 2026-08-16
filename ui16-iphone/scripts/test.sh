#!/bin/bash
# Run the protocol/state test suite (no simulator or hardware required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
echo "== UI16 Control — testes da biblioteca =="
swift test "$@"
