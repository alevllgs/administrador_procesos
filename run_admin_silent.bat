@echo off
REM =========================================================================
REM run_admin_silent.bat - Lanzador SILENCIOSO del Administrador de Procesos
REM Uso para la tarea de autoarranque o para ejecutar en segundo plano.
REM Registra toda la salida en run_logs\admin.log
REM El host y puerto se leen de .env (APP_HOST / APP_PORT).
REM =========================================================================
cd /d "%~dp0"

if not exist "run_logs" mkdir run_logs

REM --- Ruta de la app en formato R (forward slashes, sin barra final) ---
set "APPDIR=%~dp0"
set "APPDIR=%APPDIR:\=/%"
set "APPDIR=%APPDIR:~0,-1%"

REM --- Leer host/puerto desde .env ---
set "APP_HOST=0.0.0.0"
set "APP_PORT=1234"
for /f "usebackq tokens=1,* delims==" %%a in ("%~dp0.env") do (
    if /i "%%a"=="APP_HOST" set "APP_HOST=%%b"
    if /i "%%a"=="APP_PORT" set "APP_PORT=%%b"
)

set "RSCRIPT="
if exist "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" set "RSCRIPT=C:\Program Files\R\R-4.5.1\bin\Rscript.exe"
if not defined RSCRIPT if exist "C:\Program Files\R\R-4.5.0\bin\Rscript.exe" set "RSCRIPT=C:\Program Files\R\R-4.5.0\bin\Rscript.exe"
if not defined RSCRIPT if exist "C:\Program Files\R\R-4.4.2\bin\Rscript.exe" set "RSCRIPT=C:\Program Files\R\R-4.4.2\bin\Rscript.exe"

if not defined RSCRIPT (
    echo [ERROR] No se encontro Rscript.exe. Instale R y reejecute.>> "run_logs\admin.log"
    exit /b 1
)

echo [%date% %time%] Iniciando Administrador de Procesos>> "run_logs\admin.log"
echo [%date% %time%] Rscript: %RSCRIPT%>> "run_logs\admin.log"
echo [%date% %time%] Escuchando en http://%APP_HOST%:%APP_PORT%>> "run_logs\admin.log"

"%RSCRIPT%" -e "shiny::runApp(appDir = '%APPDIR%', host = '%APP_HOST%', port = %APP_PORT%, launch.browser = FALSE)" >> "run_logs\admin.log" 2>&1

echo [%date% %time%] Administrador de Procesos detenido>> "run_logs\admin.log"
