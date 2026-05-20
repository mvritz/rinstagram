# R/visualize.R

#' Plot follower growth over time
#'
#' Renders an interactive plotly chart of historical follower counts. When a
#' \code{forecast} data frame from \code{forecast_growth()} is supplied, the
#' LSTM prediction and 90 \% confidence band are overlaid.
#'
#' @param username Character. The Instagram username.
#' @param db_path Path to the SQLite database containing snapshots.
#' @param forecast Optional data frame from \code{forecast_growth()}. Must
#'   contain \code{date}, \code{predicted_followers}, \code{lower_bound},
#'   \code{upper_bound}.
#' @return A \code{plotly} HTML widget.
#' @export
#'
#' @examples
#' \dontrun{
#'   plot_growth("cristiano")
#'   plot_growth("cristiano", forecast = forecast_growth("cristiano", 30))
#' }
plot_growth <- function(username, db_path = "data/rinstagram.db", forecast = NULL) {
  con <- db_connect(db_path)
  on.exit(DBI::dbDisconnect(con))
  history <- db_get_history(con, username)

  if (nrow(history) == 0) stop("No historical data for: ", username)

  history$snapshot_date <- as.Date(history$snapshot_date)

  p <- ggplot2::ggplot(history, ggplot2::aes(x = snapshot_date, y = follower_count)) +
    ggplot2::geom_line(colour = "#405DE6", linewidth = 1.1) +
    ggplot2::geom_point(colour = "#405DE6", size = 2.5) +
    ggplot2::scale_y_continuous(labels = scales::label_comma()) +
    ggplot2::scale_x_date(date_labels = "%b %Y") +
    ggplot2::labs(
      title = paste0("Follower Growth \u2014 @", username),
      x     = NULL,
      y     = "Followers"
    ) +
    ggplot2::theme_minimal(base_size = 13) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))

  if (!is.null(forecast)) {
    forecast$date <- as.Date(forecast$date)
    p <- p +
      ggplot2::geom_ribbon(
        data    = forecast,
        mapping = ggplot2::aes(x = date, ymin = lower_bound, ymax = upper_bound),
        fill    = "#E1306C", alpha = 0.15, inherit.aes = FALSE
      ) +
      ggplot2::geom_line(
        data    = forecast,
        mapping = ggplot2::aes(x = date, y = predicted_followers),
        colour  = "#E1306C", linewidth = 1, linetype = "dashed", inherit.aes = FALSE
      )
  }

  plotly::ggplotly(p) |>
    plotly::layout(hovermode = "x unified")
}

#' Plot engagement rate distribution across profiles
#'
#' Renders a horizontal bar chart sorted by engagement rate.
#' Run \code{analyze()} on your data first.
#'
#' @param data A data frame with \code{username} and \code{engagement_rate}
#'   columns (output of \code{analyze()}).
#' @return A \code{plotly} HTML widget.
#' @export
#'
#' @examples
#' \dontrun{
#'   data <- analyze(scrape(c("cristiano", "leomessi")))
#'   plot_engagement_dist(data)
#' }
plot_engagement_dist <- function(data) {
  if (!"engagement_rate" %in% names(data)) {
    stop("Run analyze() first to compute 'engagement_rate'.")
  }

  data <- data[!is.na(data$engagement_rate), ]
  if (nrow(data) == 0) stop("No non-NA engagement_rate values to plot.")

  p <- ggplot2::ggplot(
    data,
    ggplot2::aes(
      x = stats::reorder(username, engagement_rate),
      y = engagement_rate,
      text = paste0("@", username, "\n", scales::label_percent(accuracy = 0.01)(engagement_rate))
    )
  ) +
    ggplot2::geom_col(fill = "#833AB4", alpha = 0.85) +
    ggplot2::scale_y_continuous(labels = scales::label_percent(accuracy = 0.01)) +
    ggplot2::coord_flip() +
    ggplot2::labs(
      title = "Engagement Rate by Profile",
      x     = NULL,
      y     = "Engagement Rate"
    ) +
    ggplot2::theme_minimal(base_size = 13) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))

  plotly::ggplotly(p, tooltip = "text")
}

#' Radar chart comparing multiple profiles
#'
#' Normalises five metrics to [0, 1] and renders an overlaid radar chart,
#' making it easy to compare influencer profiles at a glance.
#'
#' @param data A data frame from \code{analyze()} with at least \code{username},
#'   \code{follower_count}, \code{following_count}, \code{posts_count}, and
#'   \code{engagement_rate}.
#' @return A \code{plotly} radar chart.
#' @export
#'
#' @examples
#' \dontrun{
#'   data <- analyze(scrape(c("cristiano", "leomessi", "neymarjr")))
#'   plot_comparison(data)
#' }
plot_comparison <- function(data) {
  required <- c("username", "follower_count", "following_count", "posts_count", "engagement_rate")
  missing <- setdiff(required, names(data))
  if (length(missing) > 0) stop("Run analyze() first. Missing columns: ", paste(missing, collapse = ", "))

  norm_vec <- function(x) {
    x <- as.numeric(x)
    rng <- range(x, na.rm = TRUE)
    if (diff(rng) == 0) return(rep(0.5, length(x)))
    (x - rng[1]) / diff(rng)
  }

  metrics     <- c("follower_count", "following_count", "posts_count",
                   "engagement_rate", "follower_following_ratio")
  metrics     <- intersect(metrics, names(data))
  metric_labs <- c("Followers", "Following", "Posts", "Engagement", "F/F Ratio")[
    c("follower_count", "following_count", "posts_count",
      "engagement_rate", "follower_following_ratio") %in% metrics
  ]

  colours <- c("#405DE6", "#E1306C", "#833AB4", "#FCAF45", "#4CAF50",
               "#00BCD4", "#FF5722", "#9C27B0", "#2196F3", "#4CAF50")

  fig <- plotly::plot_ly()

  for (i in seq_len(nrow(data))) {
    vals <- sapply(metrics, function(m) norm_vec(data[[m]])[i])
    fig  <- plotly::add_trace(
      fig,
      type  = "scatterpolar",
      r     = c(vals, vals[1]),
      theta = c(metric_labs, metric_labs[1]),
      name  = paste0("@", data$username[i]),
      fill  = "toself",
      line  = list(color = colours[(i - 1) %% length(colours) + 1])
    )
  }

  plotly::layout(
    fig,
    polar       = list(radialaxis = list(visible = TRUE, range = c(0, 1))),
    title       = list(text = "Profile Comparison (Normalised)", font = list(size = 15)),
    legend      = list(orientation = "h"),
    showlegend  = TRUE
  )
}

#' Plot bot / fake account risk scores
#'
#' Renders a horizontal bar chart of bot probabilities. Bars are colour-coded:
#' green (low), amber (medium), red (high).
#'
#' @param data A data frame with \code{username} and \code{bot_probability}
#'   columns (output of \code{detect_bots()}).
#' @return A \code{plotly} HTML widget.
#' @export
#'
#' @examples
#' \dontrun{
#'   data <- detect_bots(analyze(scrape(c("account1", "account2"))))
#'   plot_bot_risk(data)
#' }
plot_bot_risk <- function(data) {
  if (!"bot_probability" %in% names(data)) stop("Run detect_bots() first.")

  data <- data[order(data$bot_probability, decreasing = TRUE), ]
  data$colour <- ifelse(
    data$bot_probability >= 0.7, "#E53935",
    ifelse(data$bot_probability >= 0.4, "#FB8C00", "#43A047")
  )

  p <- ggplot2::ggplot(
    data,
    ggplot2::aes(
      x    = stats::reorder(username, bot_probability),
      y    = bot_probability,
      fill = colour,
      text = paste0("@", username, "\n",
                    "Bot prob: ", scales::label_percent(accuracy = 1)(bot_probability))
    )
  ) +
    ggplot2::geom_col(show.legend = FALSE, alpha = 0.9) +
    ggplot2::scale_fill_identity() +
    ggplot2::scale_y_continuous(labels = scales::label_percent(), limits = c(0, 1)) +
    ggplot2::coord_flip() +
    ggplot2::geom_hline(yintercept = 0.7, linetype = "dashed", colour = "#E53935", alpha = 0.7) +
    ggplot2::geom_hline(yintercept = 0.4, linetype = "dashed", colour = "#FB8C00", alpha = 0.7) +
    ggplot2::labs(
      title = "Bot / Fake Account Risk",
      x     = NULL,
      y     = "Bot Probability"
    ) +
    ggplot2::theme_minimal(base_size = 13) +
    ggplot2::theme(plot.title = ggplot2::element_text(face = "bold"))

  plotly::ggplotly(p, tooltip = "text")
}
