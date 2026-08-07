@echo off
REM =========================================================================
REM instalar_autoarranque.bat - Registra el Administrador de Procesos como
REM tarea de Windows para que arranque automaticamente al iniciar sesion.
REM Uso: doble clic (o CMD como Administrador) en el servidor.
REM =========================================================================
cd /d "%~dp0"

set "TAREA=administrador_procesos"
set "VBS=%CD%\start_admin_hidden.vbs"

echo Instalando tarea de autoarranque: %TAREA%
echo Comando: wscript.exe "%VBS%"

schtasks /create /tn "%TAREA%" /tr "wscript.exe \"%VBS%\"" /sc ONLOGON /rl HIGHEST /f

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [OK] Tarea instalada. El Administrador de Procesos arrancara
    echo      automaticamente, SIN ventana de consola, cada vez que inicie
    echo      sesion en el servidor.
    echo      Para arrancarla ahora mismo sin esperar: schtasks /run /tn "%TAREA%"
) else (
    echo.
    echo [ERROR] No se pudo instalar la tarea. Ejecute este archivo como Administrador.
)

pause
