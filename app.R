# =========================================================================
# app.R - Administrador de Procesos del Servidor (Shiny)
# Permite ver estado, ejecutar manualmente y ver logs de los robots
# programados en Task Scheduler.
# =========================================================================

suppressPackageStartupMessages({
  library(shiny)
  library(DT)
  library(shinyjs)
})

source("helpers.R", encoding = "UTF-8")

# -------------------------------------------------------------------------
# UI
# -------------------------------------------------------------------------
ui <- uiOutput("vista")

# -------------------------------------------------------------------------
# Server
# -------------------------------------------------------------------------
server <- function(input, output, session) {
  useShinyjs()
  options(warn = -1)

  env <- leer_env()
  users <- leer_usuarios(env)
  run_dir <- file.path(directorio_app(), "run_logs")
  if (!dir.exists(run_dir)) dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)

  # --- estado de autenticacion y refresco ---
  auth <- reactiveValues(ok = FALSE, usuario = "")
  tick <- reactiveVal(Sys.time())
  # NOTA: NO hay auto-refresh. La tabla y los logs solo se actualizan cuando
  # el usuario presiona "Actualizar". Esto evita que la app lea los logs de
  # los robots a cada rato (podia interferir con procesos como el webscraping
  # mientras escriben su log) y elimina el "pestaneo" de la tabla.

  # -------------------------------------------------------------------------
  # Vista de LOGIN
  # -------------------------------------------------------------------------
  output$vista <- renderUI({
    if (!auth$ok) {
      fluidPage(
        tags$head(tags$style("
          body { background:#f0f2f5; }
          .login-box { max-width:360px; margin:12% auto; background:#fff;
                       border:1px solid #ddd; border-radius:8px; padding:28px; }
          .login-box h2 { margin-top:0; font-size:22px; }
        ")),
        div(class = "login-box",
          h2("Administrador de Procesos"),
          p("Ingrese sus credenciales para gestionar los robots del servidor."),
          textInput("usuario", "Usuario"),
          passwordInput("password", "Contrasena"),
          br(),
          actionButton("btn_login", "Ingresar", class = "btn-primary", style = "width:100%"),
          uiOutput("login_error")
        )
      )
    } else {
      # -----------------------------------------------------------------
      # Vista PRINCIPAL (dashboard)
      # -----------------------------------------------------------------
      navbarPage(
        title = "Administrador de Procesos",
        windowTitle = "Administrador de Procesos",
        tabPanel(
          "Procesos",
          fluidRow(
            column(12,
              h4(HTML(paste0("Usuario: <b>", auth$usuario, "</b>")),
                 style = "float:right;margin-top:8px;"),
              actionButton("btn_refresh_all", "Actualizar todo",
                           class = "btn-warning btn-sm", style = "float:right;margin-right:8px;margin-top:8px;"),
              actionButton("btn_logout", "Cerrar sesion",
                           class = "btn-default btn-sm", style = "float:right;margin-right:8px;margin-top:8px;")
            )
          ),
          br(),
          fluidRow(
            column(12,
              DTOutput("tabla_robots")
            )
          ),
          hr(),
          fluidRow(
            column(12,
              h4("Visor de logs"),
              fluidRow(
                column(4, selectInput("sel_log", "Proceso:", choices = NULL, width = "100%")),
                column(2, br(), actionButton("btn_refresh_log", "Actualizar", class = "btn-info btn-sm")),
                column(6, br(), textOutput("txt_log_info"))
              ),
              pre(
                id = "visor_log",
                style = "max-height:400px;overflow:auto;background:#1e1e1e;color:#d4d4d4;padding:10px;font-size:12px;white-space:pre-wrap;",
                textOutput("log_content")
              )
            )
          )
        ),
        tabPanel(
          "Historial",
          fluidRow(
            column(12,
              h4("Historial de ejecuciones manuales"),
              DTOutput("tabla_historial")
            )
          )
        )
      )
    }
  })

  # -------------------------------------------------------------------------
  # LOGIN
  # -------------------------------------------------------------------------
  observeEvent(input$btn_login, {
    u <- trimws(if (is.null(input$usuario)) "" else input$usuario)
    p <- if (is.null(input$password)) "" else input$password
    if (validar_login(u, p, users)) {
      auth$ok <- TRUE
      auth$usuario <- u
      tick(Sys.time())
    } else {
      output$login_error <- renderUI(HTML(
        '<div class="alert alert-danger" style="margin-top:12px;">Usuario o contrasena incorrectos</div>'
      ))
    }
  })

  observeEvent(input$btn_logout, {
    auth$ok <- FALSE
    auth$usuario <- ""
  })

  # -------------------------------------------------------------------------
  # DATOS DE LOS ROBOTS
  # -------------------------------------------------------------------------
  config_data <- reactive({
    tick()
    d <- leer_config()
    d <- d[d$activo == TRUE, , drop = FALSE]
    d
  })

  estados_data <- reactive({
    d <- config_data()
    if (nrow(d) == 0) return(d)
    res <- lapply(seq_len(nrow(d)), function(i) estado_robot(d[i, ], run_dir))
    d$estado <- vapply(res, function(x) x$estado, character(1))
    d$ultima_ejecucion <- vapply(res, function(x) x$last_run, character(1))
    d$pid <- vapply(res, function(x) if (is.na(x$pid)) NA_character_ else as.character(x$pid), character(1))
    d$log_ultimo <- vapply(res, function(x) if (is.null(x$log)) "" else as.character(x$log), character(1))
    d
  })

  # -------------------------------------------------------------------------
  # TABLA DE ROBOTS (construida una vez + replaceData para no "pestañear")
  # -------------------------------------------------------------------------
  build_robots_df <- function() {
    d <- estados_data()
    if (nrow(d) == 0) return(d)
    color <- function(st) {
      switch(st,
        "EJECUTANDO"   = "#17a2b8",
        "OK"           = "#28a745",
        "ERROR"        = "#dc3545",
        "SIN SALIDA"   = "#fd7e14",
        "SIN EJECUCION" = "#6c757d",
        "DESCONOCIDO"  = "#ffc107",
        "#6c757d")
    }
    d$estado_html <- sprintf('<span class="badge" style="background:%s;color:#fff;">%s</span>',
                             vapply(d$estado, color, character(1)), d$estado)

    # bloqueo de 10 minutos post-lanzamiento (esperando respuesta del server)
    lz <- lanzados()
    d$acciones <- vapply(seq_len(nrow(d)), function(i) {
      row <- d[i, ]
      botones <- character(0)

      espera_min <- 0
      if (row$id %in% names(lz)) {
        dif <- difftime(Sys.time(), lz[[row$id]], units = "mins")
        if (dif < 10) espera_min <- ceiling(10 - dif)
        else {
          lz2 <- lz; lz2[[row$id]] <- NULL; lanzados(lz2)
        }
      }

      if (row$estado == "EJECUTANDO") {
        botones <- c(botones, sprintf(
          '<button id="b_det_%s" type="button" class="btn btn-danger btn-xs"
             onclick="Shiny.setInputValue(\'btn_detener\', \'%s\', {priority:\'event\'})">Detener</button>',
          row$id, row$id))
      } else if (espera_min > 0) {
        botones <- c(botones, sprintf(
          '<button disabled class="btn btn-default btn-xs"
             title="Esperando respuesta del servidor...">Lanzando (%d min)</button>',
          espera_min))
      } else {
        botones <- c(botones, sprintf(
          '<button id="b_ej_%s" type="button" class="btn btn-success btn-xs"
             onclick="Shiny.setInputValue(\'btn_ejecutar\', \'%s\', {priority:\'event\'})">Ejecutar</button>',
          row$id, row$id))
      }
      botones <- c(botones, sprintf(
        '<button id="b_ver_%s" type="button" class="btn btn-info btn-xs"
           onclick="Shiny.setInputValue(\'btn_verlog\', \'%s\', {priority:\'event\'})">Ver log</button>',
        row$id, row$id))
      paste(botones, collapse = " ")
    }, character(1))

    d[, c("nombre", "descripcion", "estado_html", "ultima_ejecucion", "horario", "acciones")]
  }

  output$tabla_robots <- renderDT({
    df <- build_robots_df()
    if (nrow(df) == 0) {
      return(datatable(data.frame(Info = "No hay procesos configurados o activos."),
                       rownames = FALSE, options = list(dom = "t")))
    }
    datatable(
      df,
      colnames = c("Proceso", "Descripcion", "Estado", "Ultima ejecucion", "Horario", "Acciones"),
      rownames = FALSE,
      escape = FALSE,
      selection = "none",
      options = list(
        pageLength = 10,
        dom = "ftp",
        autoWidth = TRUE,
        columnDefs = list(list(width = "220px", targets = 5))
      )
    ) |> formatStyle(0, backgroundColor = "#ffffff")
  })

  proxy_robots <- dataTableProxy("tabla_robots")

  observe({
    estados_data()
    df <- build_robots_df()
    if (nrow(df) == 0) return()
    tryCatch(
      replaceData(proxy_robots, df, resetPaging = FALSE, rownames = FALSE),
      error = function(e) NULL
    )
  })

  # -------------------------------------------------------------------------
  # ELEGIR LOG EN EL VISOR
  # -------------------------------------------------------------------------
  observe({
    d <- estados_data()
    if (nrow(d) == 0) return()
    choices <- setNames(d$id, d$nombre)
    actual <- isolate(input$sel_log)
    if (is.null(actual) || !(actual %in% d$id)) {
      updateSelectInput(session, "sel_log", choices = choices, selected = d$id[1])
    } else if (!identical(names(choices), names(input$sel_log))) {
      updateSelectInput(session, "sel_log", choices = choices, selected = actual)
    }
  })

  log_tail_rv <- reactiveVal("")

  observe({
    sel <- input$sel_log
    req(sel)
    tick()
    d <- estados_data()
    if (nrow(d) == 0) { log_tail_rv("(sin procesos)"); return() }
    row <- d[d$id == sel, , drop = FALSE][1, ]
    path <- if (!is.na(row$log_ultimo) && nzchar(row$log_ultimo)) row$log_ultimo else NULL
    if (is.null(path)) {
      log_tail_rv("(sin archivo de log)")
    } else {
      contenido <- leer_log_tail(path, n = 400)
      if (!nzchar(trimws(contenido)) && row$estado == "EJECUTANDO") {
        log_tail_rv("El proceso esta en ejecucion pero aun no ha escrito salida. Puede tardar un momento en responder.")
      } else {
        log_tail_rv(contenido)
      }
    }
  })

  # Recarga MANUAL: botones "Actualizar" (visor) y "Actualizar todo" (dashboard)
  observeEvent(input$btn_refresh_log,  { tick(Sys.time()) })
  observeEvent(input$btn_refresh_all,  { tick(Sys.time()) })

  output$log_content <- renderText({
    log_tail_rv()
  })

  output$txt_log_info <- renderText({
    d <- estados_data()
    if (nrow(d) == 0) return("")
    sel <- input$sel_log
    if (is.null(sel) || !(sel %in% d$id)) return("")
    row <- d[d$id == sel, ][1, ]
    path <- row$log_ultimo
    if (is.null(path) || !nzchar(path)) return("Sin archivo de log.")
    estado <- row$estado
    paste0("Archivo: ", path, "   |   Estado: ", estado,
           "   |   Actualizado: ", format(Sys.time(), "%H:%M:%S"))
  })

  # -------------------------------------------------------------------------
  # EJECUTAR MANUALMENTE (con bloqueo anti doble-ejecucion)
  # -------------------------------------------------------------------------
  # ids de procesos en ejecucion (para bloqueo inmediato entre refrescos)
  en_ejecucion <- reactiveVal(character(0))
  # lanzamientos recientes: id -> timestamp (bloquea el boton 10 min)
  lanzados <- reactiveVal(list())

  # Actualiza el registro de procesos en ejecucion en cada refresco
  observe({
    d <- estados_data()
    en_ejecucion(names(d$id)[d$estado == "EJECUTANDO"])
  })

  observeEvent(input$btn_ejecutar, {
    id <- input$btn_ejecutar
    d <- estados_data()
    row <- d[d$id == id, ][1, ]

    # Bloqueo por lanzamiento reciente (10 min) o proceso en curso
    if (lanzado_recientemente(id, lanzados())) {
      showNotification("Se acaba de lanzar este proceso. Espere unos minutos a que responda.",
                       type = "warning", duration = 5)
      tick(Sys.time())
      return()
    }
    if (id %in% en_ejecucion() || proceso_en_curso(id, run_dir)) {
      showNotification("Este proceso ya esta en ejecucion. Espere a que termine.",
                       type = "warning", duration = 5)
      tick(Sys.time())
      return()
    }

    showModal(modalDialog(
      title = "Confirmar ejecucion",
      HTML(sprintf("Esta seguro que desea ejecutar <b>%s</b> (%s) ahora?<br><br>
                   El proceso se lanzara en segundo plano y su salida se registrara en run_logs.",
                   row$nombre, row$id)),
      footer = tagList(
        actionButton("conf_ejecutar", "Ejecutar", class = "btn-success"),
        modalButton("Cancelar")
      )
    ))
  })

  observeEvent(input$conf_ejecutar, {
    removeModal()
    d <- estados_data()
    id <- isolate(input$btn_ejecutar)
    row <- d[d$id == id, ][1, ]

    # Re-chequeo antes de lanzar (evita doble clic o modal abierto dos veces)
    if (lanzado_recientemente(id, lanzados())) {
      showNotification("Se acaba de lanzar este proceso. No se lanzo de nuevo.",
                       type = "warning", duration = 5)
      tick(Sys.time())
      return()
    }
    if (id %in% en_ejecucion() || proceso_en_curso(id, run_dir)) {
      showNotification("Este proceso ya esta en ejecucion. No se lanzo de nuevo.",
                       type = "warning", duration = 5)
      tick(Sys.time())
      return()
    }

    res <- tryCatch(
      ejecutar_robot(row, run_dir, auth$usuario),
      error = function(e) list(error = conditionMessage(e))
    )
    if (!is.null(res$error)) {
      showNotification(paste("Error al ejecutar:", res$error), type = "error")
    } else {
      lz <- lanzados()
      lz[[id]] <- Sys.time()
      lanzados(lz)
      en_ejecucion(c(en_ejecucion(), id))
      showNotification(sprintf("Proceso %s lanzado (PID %s). El boton quedara bloqueado 10 minutos mientras responde.",
                               row$id, res$pid), type = "message", duration = 8)
    }
    tick(Sys.time())
  })

  # -------------------------------------------------------------------------
  # DETENER PROCESO
  # -------------------------------------------------------------------------
  observeEvent(input$btn_detener, {
    id <- input$btn_detener
    d <- estados_data()
    row <- d[d$id == id, ][1, ]
    if (!(id %in% en_ejecucion()) || is.na(row$pid) || !proceso_vivo(row$pid)) {
      showNotification("Este proceso ya no esta en ejecucion.", type = "warning", duration = 5)
      tick(Sys.time())
      return()
    }
    showModal(modalDialog(
      title = "Confirmar detencion",
      HTML(sprintf("Desea detener <b>%s</b> (PID %s)?<br>El proceso se terminara junto con sus hijos.",
                   row$nombre, row$pid)),
      footer = tagList(
        actionButton("conf_detener", "Detener", class = "btn-danger"),
        modalButton("Cancelar")
      )
    ))
  })

  observeEvent(input$conf_detener, {
    removeModal()
    id <- isolate(input$btn_detener)
    d <- estados_data()
    row <- d[d$id == id, ][1, ]
    out <- matar_proceso(row$pid)
    registrar_historial(run_dir, row$id, row$nombre, auth$usuario,
                        paste("DETENIDO PID", row$pid), row$pid)
    showNotification("Proceso detenido", type = "warning", duration = 5)
    tick(Sys.time())
  })

  # -------------------------------------------------------------------------
  # VER LOG DESDE LA TABLA
  # -------------------------------------------------------------------------
  observeEvent(input$btn_verlog, {
    id <- input$btn_verlog
    d <- estados_data()
    if (id %in% d$id) updateSelectInput(session, "sel_log", selected = id)
    showNotification("Seleccionado en el visor de logs", type = "message", duration = 3)
  })

  # -------------------------------------------------------------------------
  # HISTORIAL
  # -------------------------------------------------------------------------
  output$tabla_historial <- renderDT({
    h <- leer_historial(run_dir)
    if (nrow(h) == 0) {
      return(datatable(data.frame(Info = "Aun no hay ejecuciones manuales registradas."),
                       rownames = FALSE, options = list(dom = "t")))
    }
    datatable(h[nrow(h):1, , drop = FALSE], rownames = FALSE,
              options = list(pageLength = 15, dom = "ftp"))
  })
}

shinyApp(ui = ui, server = server)
