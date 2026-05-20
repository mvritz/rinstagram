# R/track.R

#' Track Instagram profile growth over time
#'
#' Scrapes the specified profiles and saves a time-stamped snapshot to the
#' SQLite database. Run this regularly (e.g. daily via \code{taskscheduleR} or
#' a system cron job) to accumulate historical data for the LSTM growth
#' forecaster.
#'
#' @param usernames Character vector of Instagram usernames to track.
#' @param db_path Path to the SQLite database.
#'   Created automatically if it does not exist.
#' @param use_session Logical. When \code{TRUE}, uses an authenticated session
#'   via \code{lscrape} (higher quota, richer data). Requires
#'   \code{profile_username} and \code{profile_password}.
#' @param profile_username Instagram username for the scraping account.
#'   Only required when \code{use_session = TRUE}.
#' @param profile_password Instagram password for the scraping account.
#'   Only required when \code{use_session = TRUE}.
#' @param delay_range Numeric vector of length 2 giving the minimum and maximum
#'   random delay in seconds between requests. Default: \code{c(3, 7)}.
#' @return Invisibly returns a data frame of snapshot results, or \code{NULL}
#'   if login failed.
#' @export
#'
#' @examples
#' \dontrun{
#'   track(c("cristiano", "leomessi"))
#'
#'   track(c("cristiano", "leomessi"),
#'         use_session      = TRUE,
#'         profile_username = "my_dummy_account",
#'         profile_password = "my_password")
#' }
track <- function(usernames,
                  db_path          = "data/rinstagram.db",
                  use_session      = FALSE,
                  profile_username = NULL,
                  profile_password = NULL,
                  delay_range      = c(3, 7)) {
  if (use_session && (is.null(profile_username) || is.null(profile_password))) {
    stop("profile_username and profile_password are required when use_session = TRUE.")
  }

  con <- db_connect(db_path)
  on.exit(DBI::dbDisconnect(con))

  cli::cli_h1("rinstagram tracker")
  cli::cli_alert_info("Tracking {length(usernames)} profile{?s} on {format(Sys.Date())}")

  instagram_session <- NULL

  if (use_session) {
    cli::cli_alert_info("Logging in as {.val {profile_username}} \u2026")
    login_data <- tryCatch(
      handle_login(profile_username, profile_password),
      error = function(e) {
        cli::cli_alert_danger("Login failed: {e$message}")
        NULL
      }
    )
    if (is.null(login_data)) {
      cli::cli_alert_warning("Falling back to anonymous scraping.")
      use_session <- FALSE
    } else {
      session_id <- login_data$cookies[login_data$cookies$name == "sessionid", "value"]
      user_id    <- login_data$cookies[login_data$cookies$name == "ds_user_id",  "value"]
      instagram_session <- new(
        "InstagramSession",
        csrf       = login_data$instagram_session@csrf,
        user_agent = login_data$instagram_session@user_agent,
        session_id = session_id,
        user_id    = user_id
      )
      cli::cli_alert_success("Logged in successfully.")
    }
  }

  results <- lapply(seq_along(usernames), function(idx) {
    username <- usernames[[idx]]

    result <- tryCatch({
      profile <- if (use_session && !is.null(instagram_session)) {
        handle_graphql_request(instagram_session, username)
      } else {
        handle_web_profile_request(username)
      }

      db_save_snapshot(con, profile)

      cli::cli_alert_success(
        "[{format(Sys.time(), '%H:%M:%S')}] {.val {username}}: {.strong {format(profile@follower_count, big.mark = ',')}} followers"
      )

      data.frame(
        username        = username,
        follower_count  = profile@follower_count,
        following_count = profile@following_count,
        posts_count     = profile@posts_count,
        snapshot_date   = as.character(Sys.Date()),
        stringsAsFactors = FALSE
      )
    }, error = function(e) {
      cli::cli_alert_warning("Failed to track {.val {username}}: {e$message}")
      NULL
    })

    if (idx < length(usernames)) {
      Sys.sleep(stats::runif(1, delay_range[1], delay_range[2]))
    }

    result
  })

  df <- do.call(rbind, Filter(Negate(is.null), results))
  n_ok <- if (is.data.frame(df)) nrow(df) else 0

  cli::cli_rule()
  cli::cli_alert_success("Snapshot complete: {n_ok}/{length(usernames)} profiles tracked.")

  invisible(df)
}
