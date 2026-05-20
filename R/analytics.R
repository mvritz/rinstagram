# R/analytics.R

compute_engagement_rate <- function(avg_likes, avg_comments, follower_count) {
  if (is.na(follower_count) || follower_count == 0) return(NA_real_)
  if (is.na(avg_likes)) avg_likes <- 0
  if (is.na(avg_comments)) avg_comments <- 0
  (avg_likes + avg_comments) / follower_count
}

compute_gini <- function(x) {
  x <- x[!is.na(x) & is.finite(x)]
  if (length(x) < 2) return(NA_real_)
  x <- sort(as.numeric(x))
  n <- length(x)
  2 * sum(x * seq_len(n)) / (n * sum(x)) - (n + 1) / n
}

parse_semicolon_col <- function(x) {
  lapply(x, function(v) {
    if (is.na(v) || v == "") return(numeric(0))
    suppressWarnings(as.numeric(strsplit(as.character(v), ";\\s*")[[1]]))
  })
}

#' Analyze scraped Instagram profiles with enriched statistics
#'
#' Computes engagement rate, Gini coefficient for likes distribution,
#' follower-to-following ratio, and posting frequency from scraped data.
#'
#' @param data A data frame produced by \code{scrape()}, \code{lscrape()}, or
#'   \code{db_load_profiles()}.
#' @return The input data frame with additional columns: \code{avg_likes},
#'   \code{avg_comments}, \code{engagement_rate}, \code{follower_following_ratio},
#'   \code{likes_gini}.
#' @export
#'
#' @examples
#' \dontrun{
#'   data <- scrape(c("cristiano", "leomessi"))
#'   enriched <- analyze(data)
#' }
analyze <- function(data) {
  if (!is.data.frame(data)) stop("'data' must be a data frame.")
  required <- c("username", "follower_count", "following_count", "posts_count")
  missing_cols <- setdiff(required, names(data))
  if (length(missing_cols) > 0) {
    stop("Missing required columns: ", paste(missing_cols, collapse = ", "))
  }

  likes_list    <- if ("posts_likes"    %in% names(data)) parse_semicolon_col(data$posts_likes)    else vector("list", nrow(data))
  comments_list <- if ("posts_comments" %in% names(data)) parse_semicolon_col(data$posts_comments) else vector("list", nrow(data))

  data$avg_likes    <- sapply(likes_list,    function(x) if (length(x) == 0) NA_real_ else mean(x, na.rm = TRUE))
  data$avg_comments <- sapply(comments_list, function(x) if (length(x) == 0) NA_real_ else mean(x, na.rm = TRUE))

  data$engagement_rate <- mapply(
    compute_engagement_rate,
    data$avg_likes, data$avg_comments, as.numeric(data$follower_count)
  )

  data$follower_following_ratio <- as.numeric(data$follower_count) / pmax(as.numeric(data$following_count), 1)
  data$likes_gini               <- sapply(likes_list, compute_gini)

  data
}

#' Predict engagement rate using the ML microservice (MLP neural network)
#'
#' Sends profile features to the rinstagram ML service and returns predicted
#' engagement rates from the trained feed-forward neural network.
#'
#' @param profiles A data frame with at minimum \code{username},
#'   \code{follower_count}, \code{following_count}, \code{posts_count}.
#'   Optionally include \code{avg_likes} and \code{avg_comments} (from \code{analyze()})
#'   for higher accuracy.
#' @param ml_url Base URL of the ML service.
#'   Defaults to the \code{RINSTAGRAM_ML_URL} environment variable, falling
#'   back to \code{http://localhost:8001}.
#' @return \code{profiles} with an added \code{ml_predicted_engagement} column.
#' @export
#'
#' @examples
#' \dontrun{
#'   data <- analyze(scrape(c("cristiano")))
#'   data <- predict_engagement(data)
#' }
predict_engagement <- function(profiles,
                                ml_url = Sys.getenv("RINSTAGRAM_ML_URL", "http://localhost:8001")) {
  if (!is.data.frame(profiles)) stop("'profiles' must be a data frame.")

  payload <- jsonlite::toJSON(
    list(profiles = lapply(seq_len(nrow(profiles)), function(i) {
      list(
        username        = profiles$username[i],
        follower_count  = as.numeric(profiles$follower_count[i]),
        following_count = as.numeric(profiles$following_count[i]),
        posts_count     = as.numeric(profiles$posts_count[i]),
        avg_likes       = if ("avg_likes"    %in% names(profiles)) as.numeric(profiles$avg_likes[i])    else NA,
        avg_comments    = if ("avg_comments" %in% names(profiles)) as.numeric(profiles$avg_comments[i]) else NA
      )
    })),
    auto_unbox = TRUE, na = "null"
  )

  res <- httr::POST(
    paste0(ml_url, "/predict/engagement"),
    body   = payload, encode = "json",
    httr::add_headers("Content-Type" = "application/json")
  )
  if (httr::status_code(res) != 200) {
    stop("ML service returned HTTP ", httr::status_code(res), ": ", httr::content(res, as = "text"))
  }

  result <- jsonlite::fromJSON(httr::content(res, as = "text"))
  profiles$ml_predicted_engagement <- result$predictions
  profiles
}

#' Detect bot / fake accounts using the ML microservice (ensemble)
#'
#' Uses a soft-vote ensemble of LightGBM and a two-layer MLP to estimate the
#' probability that each profile is a bot or has purchased followers.
#'
#' @param profiles A data frame with \code{username}, \code{follower_count},
#'   \code{following_count}, \code{posts_count}. Pass the output of
#'   \code{analyze()} for best results (uses \code{engagement_rate}).
#' @param ml_url Base URL of the ML service.
#' @return \code{profiles} with added \code{bot_probability} (0–1) and
#'   \code{bot_risk_label} (\code{"low"}, \code{"medium"}, \code{"high"}).
#' @export
#'
#' @examples
#' \dontrun{
#'   data <- detect_bots(analyze(scrape(c("suspicious_account"))))
#' }
detect_bots <- function(profiles,
                         ml_url = Sys.getenv("RINSTAGRAM_ML_URL", "http://localhost:8001")) {
  if (!is.data.frame(profiles)) stop("'profiles' must be a data frame.")

  payload <- jsonlite::toJSON(
    list(profiles = lapply(seq_len(nrow(profiles)), function(i) {
      list(
        username        = profiles$username[i],
        follower_count  = as.numeric(profiles$follower_count[i]),
        following_count = as.numeric(profiles$following_count[i]),
        posts_count     = as.numeric(profiles$posts_count[i]),
        avg_likes       = if ("avg_likes"       %in% names(profiles)) as.numeric(profiles$avg_likes[i])       else NA,
        avg_comments    = if ("avg_comments"    %in% names(profiles)) as.numeric(profiles$avg_comments[i])    else NA,
        engagement_rate = if ("engagement_rate" %in% names(profiles)) as.numeric(profiles$engagement_rate[i]) else NA
      )
    })),
    auto_unbox = TRUE, na = "null"
  )

  res <- httr::POST(
    paste0(ml_url, "/predict/bot"),
    body   = payload, encode = "json",
    httr::add_headers("Content-Type" = "application/json")
  )
  if (httr::status_code(res) != 200) {
    stop("ML service returned HTTP ", httr::status_code(res), ": ", httr::content(res, as = "text"))
  }

  result <- jsonlite::fromJSON(httr::content(res, as = "text"))
  profiles$bot_probability <- result$bot_probabilities
  profiles$bot_risk_label  <- result$risk_labels
  profiles
}

#' Forecast follower growth using the ML microservice (LSTM)
#'
#' Passes historical follower time-series data (collected via \code{track()})
#' to a two-layer PyTorch LSTM that outputs multi-step forecasts with
#' Monte Carlo Dropout uncertainty intervals.
#'
#' @param username Character. The Instagram username.
#' @param horizon Integer. Forecast horizon in days. One of 30, 60, or 90.
#' @param db_path Path to the SQLite database containing snapshot history.
#' @param ml_url Base URL of the ML service.
#' @return A data frame with columns \code{date}, \code{predicted_followers},
#'   \code{lower_bound}, \code{upper_bound}.
#' @export
#'
#' @examples
#' \dontrun{
#'   forecast <- forecast_growth("cristiano", horizon = 30)
#'   plot_growth("cristiano", forecast = forecast)
#' }
forecast_growth <- function(username, horizon = 30,
                             db_path = "data/rinstagram.db",
                             ml_url  = Sys.getenv("RINSTAGRAM_ML_URL", "http://localhost:8001")) {
  if (!horizon %in% c(30L, 60L, 90L)) stop("'horizon' must be 30, 60, or 90.")

  con <- db_connect(db_path)
  on.exit(DBI::dbDisconnect(con))

  history <- db_get_history(con, username)
  if (nrow(history) < 5) {
    stop("Need at least 5 historical snapshots for '", username,
         "'. Use track() to collect data first.")
  }

  payload <- jsonlite::toJSON(list(
    username = username,
    horizon  = as.integer(horizon),
    history  = lapply(seq_len(nrow(history)), function(i) {
      list(date = history$snapshot_date[i], follower_count = as.integer(history$follower_count[i]))
    })
  ), auto_unbox = TRUE)

  res <- httr::POST(
    paste0(ml_url, "/predict/growth"),
    body   = payload, encode = "json",
    httr::add_headers("Content-Type" = "application/json")
  )
  if (httr::status_code(res) != 200) {
    stop("ML service returned HTTP ", httr::status_code(res), ": ", httr::content(res, as = "text"))
  }

  result <- jsonlite::fromJSON(httr::content(res, as = "text"))
  data.frame(
    date                = as.Date(result$dates),
    predicted_followers = result$predicted,
    lower_bound         = result$lower_bound,
    upper_bound         = result$upper_bound,
    stringsAsFactors    = FALSE
  )
}

#' Classify account content niche using the ML microservice (DistilBERT)
#'
#' Passes biography text and post captions to a fine-tuned DistilBERT model
#' that classifies the account into one of nine content niches.
#'
#' @param profiles A data frame with \code{username}. Optionally include
#'   \code{bio} and \code{captions} columns for higher accuracy.
#' @param ml_url Base URL of the ML service.
#' @return \code{profiles} with added \code{niche} and \code{niche_confidence}
#'   columns.
#' @export
#'
#' @examples
#' \dontrun{
#'   data <- classify_niche(scrape(c("gordonramsay")))
#' }
classify_niche <- function(profiles,
                            ml_url = Sys.getenv("RINSTAGRAM_ML_URL", "http://localhost:8001")) {
  if (!is.data.frame(profiles)) stop("'profiles' must be a data frame.")

  payload <- jsonlite::toJSON(
    list(profiles = lapply(seq_len(nrow(profiles)), function(i) {
      list(
        username = profiles$username[i],
        bio      = if ("bio"      %in% names(profiles)) as.character(profiles$bio[i])      else "",
        captions = if ("captions" %in% names(profiles)) as.character(profiles$captions[i]) else ""
      )
    })),
    auto_unbox = TRUE
  )

  res <- httr::POST(
    paste0(ml_url, "/predict/niche"),
    body   = payload, encode = "json",
    httr::add_headers("Content-Type" = "application/json")
  )
  if (httr::status_code(res) != 200) {
    stop("ML service returned HTTP ", httr::status_code(res), ": ", httr::content(res, as = "text"))
  }

  result <- jsonlite::fromJSON(httr::content(res, as = "text"))
  profiles$niche            <- result$niches
  profiles$niche_confidence <- result$confidences
  profiles
}
