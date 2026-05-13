@echo off
cd /d "%~dp0"
echo.
echo  ============================================
echo   MotoPlay Server
echo  ============================================
echo.

where python >nul 2>&1
if %ERRORLEVEL% neq 0 (
  echo  ERRORE: Python non trovato.
  echo  Installa: https://python.org/downloads
  pause & exit
)

python -c "import aiohttp" >nul 2>&1
if %ERRORLEVEL% neq 0 (
  echo  Installo dipendenze...
  pip install -r requirements.txt
  echo.
)

echo  Avvio server... (attendi)
echo.

REM Avvia il browser dopo 2 secondi (server ha il tempo di partire)
start /b cmd /c "timeout /t 2 /nobreak >nul && start http://localhost:8000"

REM Avvia Python in foreground (Ctrl+C per fermare)
python server.py
