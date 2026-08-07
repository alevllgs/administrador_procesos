@echo off
REM =========================================================================
REM desinstalar_autoarranque.bat - Quita la tarea de autoarranque.
REM =========================================================================
schtasks /delete /tn "administrador_procesos" /f
echo.
echo Tarea de autoarranque eliminada.
pause
