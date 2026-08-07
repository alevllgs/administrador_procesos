# Administrador de Procesos del Servidor

App Shiny que permite **ver el estado**, **ejecutar manualmente** y **ver los logs**
de los robots programados (Task Scheduler) directamente desde un navegador,
sin necesidad de entrar al servidor.

## Requisitos en el servidor

- R (la misma version que usan los robots, p.ej. R-4.5.1)
- Paquetes R: `shiny`, `DT`, `shinyjs`, `processx`
- La cuenta con la que corre la app debe tener permiso para lanzar los robots
  (normalmente la misma cuenta `Administrador` que ejecuta las tareas).

Instalar paquetes una sola vez:

```r
install.packages(c("shiny", "DT", "shinyjs", "processx"))
```

## Instalacion

1. Copiar toda esta carpeta (`administrador_procesos`) al servidor en:
   ```
   C:\administrador_procesos
   ```
2. Editar `config_robots.csv` si alguna ruta cambio (las rutas son las del server,
   p.ej. `C:\robot_bot_produccion`).
3. Editar `.env` y poner el host/puerto (credenciales del admin quedan en `users.csv`):
   ```
   APP_HOST=10.8.145.184
   APP_PORT=1234
   ```
4. Editar `users.csv` y poner los usuarios que tendran acceso (usuario,password):
   ```
   usuario,password
   admin,cambiar123
   bandurria,huairavo
   piquero,pilpilen
   ```
   (los archivos `.env` y `users.csv` NO se deben commitear).
5. Lanzar la app:
   ```
   run_admin.bat
   ```
   La app queda escuchando en `http://localhost:1234`. Desde otras PCs de la red:
   `http://<IP-DEL-SERVER>:1234`.

   > El host y el puerto se configuran en `.env` (`APP_HOST` / `APP_PORT`).
   > Se usa el puerto 1234 (quedo libre al desactivarse el Shiny anterior).
   > Para agregar/quitar usuarios, edita `users.csv` (una fila por usuario).

## Autoarranque y mantenimiento (reinicio del servidor)

La app se lanza manualmente y **NO se levanta sola** si el servidor se reinicia
(por mantenimiento, apagado, etc.). Para que arranque sola:

1. Ejecutar una sola vez en el servidor (como Administrador):
   ```
   instalar_autoarranque.bat
   ```
   Esto crea la tarea de Windows `administrador_procesos` que ejecuta
   `run_admin_silent.bat` al iniciar sesion.

2. A partir de ese momento, cada vez que alguien inicie sesion en el servidor,
   la app queda disponible automaticamente en el puerto 1234.

Despues de un reinicio del servidor por mantenimiento:

- **Si el autoarranque esta instalado**: la app vuelve sola al iniciar sesion.
- **Si no esta instalado** (o quieres levantarla de inmediato sin esperar):
  - Desde el servidor: `run_admin.bat`
  - O disparar la tarea sin esperar el logon:
    ```
    schtasks /run /tn administrador_procesos
    ```

Detener la app (por ejemplo antes de una actualizacion):

```
detener_admin.bat
```
o directamente `schtasks /end /tn administrador_procesos`.

Quitar el autoarranque si ya no se desea:

```
desinstalar_autoarranque.bat
```

La salida del arranque silencioso se registra en `run_logs/admin.log`
(util para diagnosticar si la app no arranco tras un reinicio).

## Configuracion de robots (`config_robots.csv`)

| Columna | Descripcion |
|---|---|
| `id` | Identificador unico |
| `nombre` | Nombre visible en la tabla |
| `descripcion` | Que hace el proceso |
| `ruta_server` | Ruta en el servidor (carpeta del robot) |
| `entry` | Archivo a ejecutar (`.bat` o `.R`) |
| `comando` | `cmd /c` (para `.bat`) o `Rscript` (para `.R`) |
| `heartbeat` | Archivo/patron que indica la ultima ejecucion (mtime o contenido) |
| `log_patron` | Patron glob del log a mostrar |
| `horario` | Horario programado (solo informativo) |
| `activo` | `TRUE`/`FALSE` - si aparece en el dashboard |

## Uso

- **Procesos**: tabla con estado (EJECUTANDO / OK / ERROR / SIN EJECUCION /
  DESCONOCIDO), ultima ejecucion y botones:
  - `Ejecutar` -> lanza el proceso en segundo plano (la salida se guarda en
    `run_logs/<id>_<fecha>.log` y se registra en el historial).
  - `Detener` -> termina el proceso y sus hijos (taskkill /T /F).
  - `Ver log` -> muestra el log en el visor inferior.
- **Visor de logs**: selecciona un proceso y presiona `Actualizar` (el botón del
  visor) para refrescar el log. **No hay auto-refresh**.
- **Actualizar todo**: botón naranja arriba a la derecha que refresca la tabla
  de estados y los logs de una vez.
- **Historial**: registro de ejecuciones manuales (quien, cuando, que pid).
- Los estados se actualizan **solo al presionar** "Actualizar todo" (o al
  ejecutar/detener un proceso). No hay polling automático: esto evita que la
  app lea los logs de los robots a cada rato (podia interferir con procesos
  como el webscraping mientras escriben su log).

## Notas

- Los logs pueden estar en latin1 (server). La app normaliza la lectura a UTF-8.
- Los `run_logs/` y `.env` estan en `.gitignore` (no subir credenciales).
- La ejecucion manual usa `processx` y el PID se guarda en `run_logs/<id>.pid`
  para poder detener el proceso si la app se reinicia.
- La app se debe lanzar SIEMPRE con la cuenta que tiene permisos para correr
  los robots.
