library(shiny)
library(shinydashboard)
library(plotly)
library(DT)
library(rinstagram)

server <- function(input, output, session) {
  db_path <- Sys.getenv("RINSTAGRAM_DB_PATH", "data/rinstagram.db")
  ml_url  <- Sys.getenv("RINSTAGRAM_ML_URL",  "http://localhost:8001")

  # ── Status indicators ──────────────────────────────────────────────────────
  output$db_status <- renderText({
    if (file.exists(db_path)) "connected" else "not found"
  })

  output$ml_status <- renderText({
    tryCatch({
      res <- httr::GET(paste0(ml_url, "/health"), httr::timeout(2))
      if (httr::status_code(res) == 200) "online" else "offline"
    }, error = function(e) "offline")
  })

  # ── Shared reactive: all profiles from DB ─────────────────────────────────
  all_profiles <- reactive({
    if (!file.exists(db_path)) return(data.frame())
    con <- db_connect(db_path)
    on.exit(DBI::dbDisconnect(con))
    db_load_profiles(con)
  })

  all_usernames <- reactive({
    df <- all_profiles()
    if (nrow(df) == 0) character(0) else sort(unique(df$username))
  })

  observe({
    users <- all_usernames()
    updateSelectInput(session, "growth_username",    choices = users)
    updateSelectizeInput(session, "compare_usernames", choices = users)
    updateSelectizeInput(session, "bot_usernames",     choices = users)
  })

  # ══════════════════════════════════════════════════════════════════════════
  # Profile Explorer
  # ══════════════════════════════════════════════════════════════════════════

  explorer_data <- eventReactive(input$explorer_go, {
    req(nzchar(input$explorer_username))
    username <- trimws(input$explorer_username)

    withProgress(message = "Scraping profile...", value = 0.3, {
      data <- tryCatch(scrape(username, db_path = db_path, file_path = NULL), error = function(e) NULL)
      if (is.null(data)) return(NULL)
      setProgress(value = 0.6, message = "Running analysis...")
      data <- analyze(data)
      setProgress(value = 0.8, message = "Running ML predictions...")
      data <- tryCatch(predict_engagement(data, ml_url), error = function(e) { data$ml_predicted_engagement <- NA; data })
      data <- tryCatch(detect_bots(data, ml_url),        error = function(e) { data$bot_probability <- NA; data$bot_risk_label <- "unknown"; data })
      data <- tryCatch(classify_niche(data, ml_url),     error = function(e) { data$niche <- "unknown"; data$niche_confidence <- NA; data })
    })
    data
  })

  output$vb_followers <- renderValueBox({
    data <- explorer_data()
    valueBox(
      if (is.null(data)) "—" else format(data$follower_count, big.mark = ","),
      "Followers", icon = icon("users"), color = "blue"
    )
  })

  output$vb_following <- renderValueBox({
    data <- explorer_data()
    valueBox(
      if (is.null(data)) "—" else format(data$following_count, big.mark = ","),
      "Following", icon = icon("user-plus"), color = "purple"
    )
  })

  output$vb_posts <- renderValueBox({
    data <- explorer_data()
    valueBox(
      if (is.null(data)) "—" else format(data$posts_count, big.mark = ","),
      "Posts", icon = icon("images"), color = "red"
    )
  })

  output$vb_engagement <- renderValueBox({
    data <- explorer_data()
    val <- if (is.null(data) || is.na(data$engagement_rate)) "N/A" else scales::label_percent(accuracy = 0.01)(data$engagement_rate)
    valueBox(val, "Engagement Rate", icon = icon("heart"), color = "yellow")
  })

  output$explorer_engagement_gauge <- renderPlotly({
    data <- explorer_data()
    val  <- if (!is.null(data) && !is.na(data$ml_predicted_engagement)) data$ml_predicted_engagement else 0

    plotly::plot_ly(
      type  = "indicator",
      mode  = "gauge+number+delta",
      value = round(val * 100, 2),
      number = list(suffix = "%"),
      gauge = list(
        axis      = list(range = list(0, 15), ticksuffix = "%"),
        bar       = list(color = "#FCAF45"),
        steps     = list(
          list(range = c(0, 3),   color = "#ffecd2"),
          list(range = c(3, 8),   color = "#fcb045"),
          list(range = c(8, 15),  color = "#fd1d1d")
        ),
        threshold = list(line = list(color = "#833AB4", width = 4), value = val * 100)
      ),
      title = list(text = "Predicted Engagement Rate")
    ) |> plotly::layout(margin = list(t = 50, b = 20))
  })

  output$explorer_bot_gauge <- renderPlotly({
    data <- explorer_data()
    val  <- if (!is.null(data) && !is.na(data$bot_probability)) data$bot_probability else 0

    plotly::plot_ly(
      type  = "indicator",
      mode  = "gauge+number",
      value = round(val * 100, 1),
      number = list(suffix = "%"),
      gauge = list(
        axis  = list(range = list(0, 100), ticksuffix = "%"),
        bar   = list(color = if (val >= 0.7) "#E53935" else if (val >= 0.4) "#FB8C00" else "#43A047"),
        steps = list(
          list(range = c(0,  40),  color = "#e8f5e9"),
          list(range = c(40, 70),  color = "#fff3e0"),
          list(range = c(70, 100), color = "#ffebee")
        )
      ),
      title = list(text = "Bot Probability")
    ) |> plotly::layout(margin = list(t = 50, b = 20))
  })

  output$explorer_niche <- renderUI({
    data <- explorer_data()
    if (is.null(data)) return(tags$p("Run a search first."))

    niche      <- if (!is.na(data$niche)) data$niche else "unknown"
    confidence <- if (!is.na(data$niche_confidence)) scales::label_percent(accuracy = 1)(data$niche_confidence) else "N/A"

    niche_icons <- list(
      fitness = "dumbbell", food = "utensils", travel = "plane",
      fashion = "tshirt", tech = "laptop-code", lifestyle = "sun",
      art = "palette", sports = "trophy", other = "star"
    )
    icon_name <- niche_icons[[niche]] %||% "star"

    tags$div(
      style = "text-align: center; padding: 20px;",
      tags$h2(icon(icon_name), " ", tools::toTitleCase(niche),
              style = "color: #833AB4; font-size: 2.5rem;"),
      tags$p(paste("Confidence:", confidence), style = "font-size: 1.1rem; color: #666;")
    )
  })

  # ══════════════════════════════════════════════════════════════════════════
  # Growth Tracker
  # ══════════════════════════════════════════════════════════════════════════

  growth_data <- eventReactive(input$growth_go, {
    req(input$growth_username)
    list(
      username = input$growth_username,
      horizon  = as.integer(input$growth_horizon),
      forecast_on = input$growth_forecast_on
    )
  })

  output$growth_chart <- renderPlotly({
    gd <- growth_data()
    req(gd)

    forecast <- NULL
    if (gd$forecast_on) {
      forecast <- tryCatch(
        forecast_growth(gd$username, gd$horizon, db_path, ml_url),
        error = function(e) NULL
      )
    }

    tryCatch(
      plot_growth(gd$username, db_path, forecast),
      error = function(e) {
        plotly::plot_ly() |> plotly::layout(title = paste("No data for:", gd$username))
      }
    )
  })

  growth_history <- reactive({
    gd <- growth_data()
    req(gd)
    con <- db_connect(db_path)
    on.exit(DBI::dbDisconnect(con))
    db_get_history(con, gd$username)
  })

  output$growth_vb_current <- renderValueBox({
    h <- growth_history()
    val <- if (nrow(h) == 0) "—" else format(h$follower_count[nrow(h)], big.mark = ",")
    valueBox(val, "Current Followers", icon = icon("users"), color = "blue")
  })

  output$growth_vb_change <- renderValueBox({
    h <- growth_history()
    if (nrow(h) < 2) return(valueBox("—", "Change", icon = icon("chart-line"), color = "green"))
    change <- h$follower_count[nrow(h)] - h$follower_count[1]
    col    <- if (change >= 0) "green" else "red"
    valueBox(paste0(if (change >= 0) "+" else "", format(change, big.mark = ",")),
             "Total Change", icon = icon("chart-line"), color = col)
  })

  output$growth_vb_forecast90 <- renderValueBox({
    gd <- growth_data()
    req(gd)
    fc <- tryCatch(forecast_growth(gd$username, 90, db_path, ml_url), error = function(e) NULL)
    val <- if (is.null(fc)) "N/A" else format(round(fc$predicted_followers[nrow(fc)]), big.mark = ",")
    valueBox(val, "90-Day Forecast", icon = icon("crystal-ball"), color = "purple")
  })

  # ══════════════════════════════════════════════════════════════════════════
  # Comparison
  # ══════════════════════════════════════════════════════════════════════════

  comparison_data <- eventReactive(input$compare_go, {
    req(length(input$compare_usernames) >= 2)
    con <- db_connect(db_path)
    on.exit(DBI::dbDisconnect(con))
    raw <- db_load_profiles(con, input$compare_usernames)
    analyze(raw)
  })

  output$compare_radar <- renderPlotly({
    data <- comparison_data()
    tryCatch(plot_comparison(data), error = function(e) plotly::plot_ly())
  })

  output$compare_engagement <- renderPlotly({
    data <- comparison_data()
    tryCatch(plot_engagement_dist(data), error = function(e) plotly::plot_ly())
  })

  # ══════════════════════════════════════════════════════════════════════════
  # Leaderboard
  # ══════════════════════════════════════════════════════════════════════════

  leaderboard_data <- reactive({
    input$lb_refresh
    con <- db_connect(db_path)
    on.exit(DBI::dbDisconnect(con))
    raw <- db_load_profiles(con)
    if (nrow(raw) == 0) return(data.frame())
    data <- analyze(raw)
    sort_col <- input$lb_sort_by %||% "engagement_rate"
    if (sort_col %in% names(data)) {
      data <- data[order(data[[sort_col]], decreasing = TRUE, na.last = TRUE), ]
    }
    data[, intersect(c("username", "follower_count", "following_count", "posts_count",
                       "avg_likes", "avg_comments", "engagement_rate",
                       "follower_following_ratio"), names(data)), drop = FALSE]
  })

  output$leaderboard_table <- renderDT({
    data <- leaderboard_data()
    if (nrow(data) == 0) return(datatable(data.frame(Message = "No data. Run scrape() first.")))

    names(data) <- gsub("_", " ", tools::toTitleCase(names(data)))
    datatable(
      data,
      extensions = "Buttons",
      options    = list(
        dom        = "Bfrtip",
        buttons    = c("copy", "csv", "excel"),
        pageLength = 20,
        scrollX    = TRUE
      ),
      rownames = FALSE
    ) |>
      formatRound(columns = intersect(c("Engagement Rate", "Follower Following Ratio", "Likes Gini"), names(data)), digits = 4) |>
      formatCurrency(columns = intersect(c("Follower Count", "Following Count", "Posts Count", "Avg Likes", "Avg Comments"), names(data)),
                     currency = "", digits = 0, mark = ",")
  })

  # ══════════════════════════════════════════════════════════════════════════
  # Bot Detector
  # ══════════════════════════════════════════════════════════════════════════

  bot_results <- eventReactive(input$bot_go, {
    req(length(input$bot_usernames) >= 1)
    con <- db_connect(db_path)
    on.exit(DBI::dbDisconnect(con))
    raw  <- db_load_profiles(con, input$bot_usernames)
    data <- analyze(raw)
    withProgress(message = "Running bot detection...", value = 0.5, {
      data <- tryCatch(detect_bots(data, ml_url), error = function(e) {
        data$bot_probability <- NA
        data$bot_risk_label  <- "error"
        data
      })
    })
    data
  })

  output$bot_chart <- renderPlotly({
    data <- bot_results()
    tryCatch(plot_bot_risk(data), error = function(e) plotly::plot_ly())
  })

  output$bot_table <- renderDT({
    data <- bot_results()
    display <- data[, intersect(c("username", "follower_count", "engagement_rate",
                                  "follower_following_ratio", "bot_probability", "bot_risk_label"),
                                names(data)), drop = FALSE]
    datatable(display, rownames = FALSE, options = list(pageLength = 10, scrollX = TRUE)) |>
      formatRound(columns = intersect(c("engagement_rate", "follower_following_ratio", "bot_probability"), names(display)), digits = 4)
  })
}

`%||%` <- function(x, y) if (!is.null(x) && length(x) > 0) x else y
