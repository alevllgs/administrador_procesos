@echo off
REM =========================================================================
REM run_admin.bat - Lanzador del Administrador de Procesos (Shiny)
REM Ejecutar en el servidor con la cuenta que tenga permiso para lanzar
REM los procesos (la misma que corre los robots).
REM El host y puerto se leen de .env (APP_HOST / APP_PORT).
REM =========================================================================
cd /d "%~dp0"

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
    echo [ERROR] No se encontro Rscript.exe. Instale R y reejecute.
    pause
    exit /b 1
)

echo [INFO] Usando Rscript: %RSCRIPT%
echo [INFO] Iniciando Administrador de Procesos en http://localhost:%APP_PORT%
echo [INFO] (accesible desde otras PCs como http://IP-DEL-SERVER:%APP_PORT%)
echo [INFO] Presione Ctrl+C para detener.
echo.

"%RSCRIPT%" -e "shiny::runApp(appDir = '%APPDIR%', host = '%APP_HOST%', port = %APP_PORT%, launch.browser = TRUE)"

pause
