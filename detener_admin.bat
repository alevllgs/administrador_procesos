@echo off
REM =========================================================================
REM detener_admin.bat - Detiene el Administrador de Procesos que este corriendo
REM (el proceso que escucha en el puerto de la app, leido de .env APP_PORT).
REM Uso: despues de una mantenimiento, o antes de reinstalar la app.
REM =========================================================================
cd /d "%~dp0"

REM --- Leer puerto desde .env ---
set "APP_PORT=1234"
for /f "usebackq tokens=1,* delims==" %%a in ("%~dp0.env") do (
    if /i "%%a"=="APP_PORT" set "APP_PORT=%%b"
)

echo Deteniendo Administrador de Procesos (puerto %APP_PORT%)...

powershell -NoProfile -Command "$p = Get-NetTCPConnection -LocalPort %APP_PORT% -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess; if ($p) { Stop-Process -Id $p -Force; Write-Output ('Detenido proceso PID ' + $p) } else { Write-Output ('No habia proceso escuchando en el puerto %APP_PORT%.') }"

echo.
echo Listo.
pause
