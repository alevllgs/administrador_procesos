# =========================================================================
# helpers.R - Funciones de apoyo para el Administrador de Procesos
# =========================================================================

# -------------------------------------------------------------------------
# Directorio de la aplicacion (Shiny lo fija con setwd al arrancar)
# -------------------------------------------------------------------------
directorio_app <- function() {
  getwd()
}

# -------------------------------------------------------------------------
# Lectura de .env (credenciales y configuracion)
# -------------------------------------------------------------------------
leer_env <- function() {
  env <- list(
    ADMIN_USER = "admin",
    ADMIN_PASS = "cambiar123",
    APP_HOST   = "0.0.0.0",
    APP_PORT   = "3838"
  )
  f <- file.path(directorio_app(), ".env")
  if (file.exists(f)) {
    for (line in readLines(f, warn = FALSE)) {
      line <- trimws(line)
      if (nchar(line) == 0 || startsWith(line, "#")) next
      kv <- strsplit(line, "=", fixed = TRUE)[[1]]
      if (length(kv) == 2) env[[trimws(kv[1])]] <- trimws(kv[2])
    }
  }
  env
}

# -------------------------------------------------------------------------
# Lectura de la configuracion de robots
# -------------------------------------------------------------------------
leer_config <- function() {
  f <- file.path(directorio_app(), "config_robots.csv")
  read.csv(f, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
}

# -------------------------------------------------------------------------
# Lectura de usuarios (users.csv) con respaldo en .env
# -------------------------------------------------------------------------
leer_usuarios <- function(env) {
  f <- file.path(directorio_app(), "users.csv")
  if (file.exists(f)) {
    d <- tryCatch(
      read.csv(f, stringsAsFactors = FALSE, fileEncoding = "UTF-8"),
      error = function(e) NULL
    )
    if (!is.null(d) && nrow(d) > 0) {
      return(d)
    }
  }
  # respaldo: un solo usuario desde .env
  data.frame(usuario = env$ADMIN_USER, password = env$ADMIN_PASS,
             stringsAsFactors = FALSE)
}

validar_login <- function(usuario, password, users) {
  i <- which(tolower(trimws(users$usuario)) == tolower(trimws(usuario)))
  length(i) > 0 && identical(password, users$password[i[1]])
}

# -------------------------------------------------------------------------
# Verificar si un robot fue lanzado hace menos de 10 minutos
# (para bloquear el boton mientras el server no responde)
# -------------------------------------------------------------------------
lanzado_recientemente <- function(id, lanzados, ventana_min = 10) {
  if (!(id %in% names(lanzados))) return(FALSE)
  t <- lanzados[[id]]
  if (!inherits(t, "POSIXct")) return(FALSE)
  difftime(Sys.time(), t, units = "mins") < ventana_min
}

# -------------------------------------------------------------------------
# Verificar si un PID esta vivo en Windows
# (usamos PowerShell porque system2/tasklist /FI falla con args con espacios)
# -------------------------------------------------------------------------
proceso_vivo <- function(pid) {
  if (is.na(pid) || !nzchar(as.character(pid))) return(FALSE)
  out <- suppressWarnings(system2(
    "powershell",
    c("-NoProfile", "-Command",
      sprintf("(Get-Process -Id %d -ErrorAction SilentlyContinue).Id", as.integer(pid))),
    stdout = TRUE, stderr = FALSE
  ))
  any(grepl(sprintf("\\b%s\\b", as.integer(pid)), out))
}

# -------------------------------------------------------------------------
# Verificar si un robot ya esta en curso (PID vivo o inicio reciente)
# -------------------------------------------------------------------------
proceso_en_curso <- function(id, run_dir) {
  pid_file <- file.path(run_dir, paste0(id, ".pid"))
  if (file.exists(pid_file)) {
    pid <- trimws(readLines(pid_file, warn = FALSE)[1])
    if (proceso_vivo(pid)) return(TRUE)
    # PID muerto: limpiar archivos obsoletos
    file.remove(pid_file)
    unlink(file.path(run_dir, paste0(id, ".inicio")))
    return(FALSE)
  }
  # Sin pid: revisar si hubo ejecucion manual en los ultimos 90 segundos
  inicio_file <- file.path(run_dir, paste0(id, ".inicio"))
  if (file.exists(inicio_file)) {
    t_inicio <- suppressWarnings(as.POSIXct(readLines(inicio_file, warn = FALSE)[1]))
    if (!is.na(t_inicio) && difftime(Sys.time(), t_inicio, units = "secs") < 90) {
      return(TRUE)
    }
    unlink(inicio_file)
  }
  FALSE
}

# -------------------------------------------------------------------------
# Ultimo archivo de log segun patron (globbing)
# -------------------------------------------------------------------------
ultimo_log <- function(row) {
  patron <- file.path(row$ruta_server, row$log_patron)
  archivos <- Sys.glob(patron)
  if (length(archivos) == 0) return(NULL)
  archivos[which.max(file.info(archivos)$mtime)]
}

# -------------------------------------------------------------------------
# Ultimo log de ejecucion manual para un robot (run_logs/<id>_*.log)
# -------------------------------------------------------------------------
ultimo_log_manual <- function(run_dir, id) {
  archivos <- Sys.glob(file.path(run_dir, paste0(id, "_*.log")))
  if (length(archivos) == 0) return(NULL)
  archivos[which.max(file.info(archivos)$mtime)]
}

# -------------------------------------------------------------------------
# Leer las ultimas lineas de un log (con fallback de encoding latin1)
# -------------------------------------------------------------------------
leer_log_tail <- function(path, n = 200, max_bytes = 200 * 1024) {
  if (is.null(path) || !file.exists(path)) return("(sin log)")
  sz <- file.info(path)$size
  con <- file(path, open = "rb")
  on.exit(close(con))
  if (sz > max_bytes) seek(con, sz - max_bytes)
  bytes <- readBin(con, "raw", n = max_bytes)
  txt <- rawToChar(bytes)
  if (!validUTF8(txt)) {
    txt <- tryCatch(iconv(txt, from = "latin1", to = "UTF-8"), error = function(e) txt)
  }
  lineas <- strsplit(txt, "\r?\n")[[1]]
  paste(tail(lineas, n), collapse = "\n")
}

# -------------------------------------------------------------------------
# Ultima ejecucion de un robot (desde heartbeat o mtime del log)
# -------------------------------------------------------------------------
obtener_ultima_ejecucion <- function(row, log_path) {
  hb <- Sys.glob(file.path(row$ruta_server, row$heartbeat))
  if (length(hb) > 0) {
    hb_path <- hb[which.max(file.info(hb)$mtime)]
    contenido <- trimws(readLines(hb_path, warn = FALSE)[1])
    # Intentar parsear contenido como timestamp ("2026-08-05 10:22:20...")
    t <- suppressWarnings(as.POSIXct(substr(contenido, 1, 19), format = "%Y-%m-%d %H:%M:%S"))
    if (!is.na(t)) return(format(t, "%Y-%m-%d %H:%M:%S"))
    return(format(file.info(hb_path)$mtime, "%Y-%m-%d %H:%M:%S"))
  }
  if (!is.null(log_path)) return(format(file.info(log_path)$mtime, "%Y-%m-%d %H:%M:%S"))
  "nunca"
}

# -------------------------------------------------------------------------
# Estado de un robot
#   -> EJECUTANDO | OK | ERROR | SIN EJECUCION | DESCONOCIDO
# -------------------------------------------------------------------------
estado_robot <- function(row, run_dir) {
  id <- row$id

  # 1) Esta corriendo ahora?
  pid <- NA
  pid_file <- file.path(run_dir, paste0(id, ".pid"))
  if (file.exists(pid_file)) {
    pid <- trimws(readLines(pid_file, warn = FALSE)[1])
    if (!proceso_vivo(pid)) {
      file.remove(pid_file)
      pid <- NA
    }
  }
  if (!is.na(pid)) {
    # Si corre, mostramos el log de la ejecucion manual (donde processx
    # redirige la salida) para ver el avance en vivo.
    log_manual <- ultimo_log_manual(run_dir, id)
    return(list(estado = "EJECUTANDO", last_run = "",
                pid = pid, log = log_manual))
  }

  # 2) Ultimo log y ultima ejecucion
  #    Si existe una ejecucion manual, priorizarla sobre el log del robot.
  log_manual <- ultimo_log_manual(run_dir, id)
  if (!is.null(log_manual)) {
    log_path <- log_manual
  } else {
    log_path <- ultimo_log(row)
  }
  log_tail <- if (!is.null(log_path)) leer_log_tail(log_path, 150) else ""
  last_run <- obtener_ultima_ejecucion(row, log_path)

  # 3) Clasificar
  #    Un log de ejecucion manual que existe jamas es "SIN EJECUCION".
  #    (aquí el proceso ya NO esta vivo: si el log manual esta vacio,
  #     significa que el proceso termino sin emitir salida = algo fallo al arrancar)
  hay_log_manual <- !is.null(log_manual)
  if (hay_log_manual && nchar(log_tail) == 0) {
    estado <- "SIN SALIDA"
  } else if (!hay_log_manual && nchar(log_tail) == 0) {
    estado <- "SIN EJECUCION"
  } else if (grepl("\\[ERROR\\]|ERROR:|fallaron|FALLO|Fallo|error critico|Error critico|Proceso abortado|Todos los reintentos fallaron",
                   log_tail, ignore.case = TRUE)) {
    estado <- "ERROR"
  } else if (grepl("PROCESO FINALIZADO|completado exitosamente|FINALIZADO EXITOSAMENTE|Proceso completo finalizado|Proceso completo de prueba finalizado|TODO OK",
                   log_tail, ignore.case = TRUE)) {
    estado <- "OK"
  } else {
    estado <- "DESCONOCIDO"
  }

  list(estado = estado, last_run = last_run, pid = NA, log = log_path)
}

# -------------------------------------------------------------------------
# Ejecutar un robot en background con processx
# -------------------------------------------------------------------------
ejecutar_robot <- function(row, run_dir, usuario) {
  ruta    <- row$ruta_server
  entry   <- row$entry
  comando <- row$comando
  ts      <- format(Sys.time(), "%Y%m%d_%H%M%S")
  log_manual <- file.path(run_dir, paste0(row$id, "_", ts, ".log"))

  entry_path <- file.path(ruta, entry)
  if (comando == "cmd /c") {
    # processx pasa los args directos a CreateProcess: sin shQuote
    proc <- processx::process$new(
      "cmd.exe",
      c("/c", entry_path),
      wd = ruta,
      stdout = log_manual,
      stderr = log_manual
    )
  } else { # Rscript
    rscript <- file.path(R.home("bin"), "Rscript.exe")
    proc <- processx::process$new(
      rscript,
      c(entry_path),
      wd = ruta,
      stdout = log_manual,
      stderr = log_manual
    )
  }

  pid <- proc$get_pid()
  writeLines(as.character(pid), file.path(run_dir, paste0(row$id, ".pid")))
  writeLines(format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
             file.path(run_dir, paste0(row$id, ".inicio")))

  registrar_historial(run_dir, row$id, row$nombre, usuario, "EJECUTADO", pid)
  list(pid = pid, log = log_manual)
}

# -------------------------------------------------------------------------
# Detener un proceso (taskkill en arbol)
# -------------------------------------------------------------------------
matar_proceso <- function(pid) {
  if (is.na(pid) || !nzchar(as.character(pid))) return("PID invalido")
  out <- suppressWarnings(system2("taskkill", c("/PID", as.character(pid), "/T", "/F"),
                                  stdout = TRUE, stderr = TRUE))
  paste(out, collapse = "\n")
}

# -------------------------------------------------------------------------
# Historial de ejecuciones manuales (CSV separado por ';')
# -------------------------------------------------------------------------
historial_file <- function(run_dir) {
  file.path(run_dir, "historial.csv")
}

leer_historial <- function(run_dir) {
  f <- historial_file(run_dir)
  if (!file.exists(f)) return(data.frame())
  read.csv(f, stringsAsFactors = FALSE, sep = ";", fileEncoding = "UTF-8")
}

registrar_historial <- function(run_dir, id, nombre, usuario, accion, pid) {
  f <- historial_file(run_dir)
  df <- data.frame(
    fecha = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    robot_id = id,
    robot = nombre,
    usuario = usuario,
    accion = accion,
    pid = pid,
    stringsAsFactors = FALSE
  )
  if (file.exists(f)) {
    write.table(df, f, append = TRUE, sep = ";", row.names = FALSE, col.names = FALSE)
  } else {
    write.table(df, f, sep = ";", row.names = FALSE, col.names = TRUE)
  }
}
