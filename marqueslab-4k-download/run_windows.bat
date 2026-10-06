@echo off
REM Executa o aplicativo a partir do codigo-fonte (desenvolvimento).
REM O usuario final nao precisa disto: basta o instalador ou o pacote portatil.
cd /d "%~dp0"
python -m pip install -r requirements.txt
python app.py
