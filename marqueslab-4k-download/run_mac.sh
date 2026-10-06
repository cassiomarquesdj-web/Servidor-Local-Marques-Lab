#!/bin/sh
# Executa o aplicativo a partir do código-fonte (desenvolvimento).
# O usuário final não precisa disto: basta o DMG.
set -e
cd "$(dirname "$0")"
python3 -m pip install -r requirements.txt
python3 app.py
