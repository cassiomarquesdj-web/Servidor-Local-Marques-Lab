@echo off
REM Executa o aplicativo a partir do codigo-fonte (desenvolvimento).
cd /d "%~dp0"
python -m pip install -r requirements.txt
python app.py
