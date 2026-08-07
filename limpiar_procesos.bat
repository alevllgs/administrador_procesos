@echo off
REM =========================================================================
REM limpiar_procesos.bat - LIBERA archivos bloqueados en el server
REM =========================================================================
REM UTILIZAR CUANDO NO DEJE COPIAR/BORRAR ARCHIVOS porque diga
REM "El archivo esta siendo utilizado por otro proceso".
REM
REM Que hace (SOLO procesos de la app y del webscraping, NO los robots):
REM   1. Mata chrome.exe y chromedriver.exe  (residuos de webscraping colgado)
REM   2. Mata Rscript que este corriendo la app (administrador_procesos)
REM   3. Mata wscript / cscript / cmd que lanzaron la app
REM
REM Ejecutar como Administrador, con DOBLE CLIC, en el server.
REM =========================================================================

echo.
echo ============================================================
echo   LIBERANDO PROCESOS BLOQUEADOS (app admin + webscraping)
echo ============================================================
echo.

REM --- 1. Matar Chrome y chromedriver (residuos de webscraping) ---
echo [1/4] Terminando Chrome y chromedriver...
taskkill /IM chrome.exe /F 2>nul
taskkill /IM chromedriver.exe /F 2>nul

REM --- 2. Matar Rscript que ejecute la app (administrador_procesos) ---
echo [2/4] Terminando Rscript de la app...
powershell -NoProfile -Command ^
  "Get-CimInstance Win32_Process -Filter \"Name='Rscript.exe'\" | Where-Object { $_.CommandLine -like '*administrador_procesos*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Output ('  terminado Rscript PID ' + $_.ProcessId) }"

REM --- 3. Matar wscript/cscript que lanzo la app ---
echo [3/4] Terminando wscript/cscript de la app...
powershell -NoProfile -Command ^
  "Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'wscript.exe' -or $_.Name -eq 'cscript.exe') -and $_.CommandLine -like '*administrador_procesos*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Output ('  terminado ' + $_.Name + ' PID ' + $_.ProcessId) }"

REM --- 4. Matar cmd que lanzo la app (run_admin.bat) ---
echo [4/4] Terminando cmd de la app...
powershell -NoProfile -Command ^
  "Get-CimInstance Win32_Process -Filter \"Name='cmd.exe'\" | Where-Object { $_.CommandLine -like '*administrador_procesos*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; Write-Output ('  terminado cmd PID ' + $_.ProcessId) }"

echo.
echo ============================================================
echo   LISTO. Espere 5 segundos y vuelva a copiar los archivos.
echo ============================================================
echo.
echo   NOTA: si aun dice "en uso", puede ser la ventana de este
echo   mismo script (cierrelo) o un Chrome/explorador abierto.
timeout /t 5 /nobreak > nul
