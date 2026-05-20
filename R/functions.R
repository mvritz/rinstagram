# R/functions.R

#' Scrape Instagram profiles (anonymous)
#'
#' Scrapes public Instagram profiles without an authenticated session.
#' For higher volumes or richer post-level data, use \code{\link{lscrape}}.
#'
#' @param usernames Character vector of Instagram usernames.
#' @param file_path Optional path for legacy CSV output. Set to \code{NULL}
#'   to disable CSV writing (data is still returned as a data frame).
#' @param db_path Path to the SQLite database for persistent storage.
#'   Set to \code{NULL} to disable database persistence.
#' @param delay_range Numeric vector \code{c(min, max)} giving the random
#'   inter-request delay in seconds. Default: \code{c(3, 7)}.
#' @param max_retries Maximum number of retry attempts per username.
#' @return A data frame with columns \code{username}, \code{follower_count},
#'   \code{following_count}, \code{posts_count}, or \code{NULL} on total failure.
#' @export
#'
#' @examples
#' \dontrun{
#'   data <- scrape(c("cristiano", "leomessi"))
#' }
scrape <- function(usernames,
                   file_path   = "data/profiles.csv",
                   db_path     = "data/rinstagram.db",
                   delay_range = c(3, 7),
                   max_retries = 3L) {
  cli::cli_h1("rinstagram scraper (anonymous)")
  cli::cli_alert_info("Scraping {length(usernames)} profile{?s}")

  con <- if (!is.null(db_path)) db_connect(db_path) else NULL
  on.exit(if (!is.null(con)) DBI::dbDisconnect(con))

  profiles <- lapply(seq_along(usernames), function(idx) {
    username <- usernames[[idx]]
    retry    <- 0L
    result   <- NULL

    while (retry < max_retries && is.null(result)) {
      tryCatch({
        profile <- handle_web_profile_request(username)

        if (!is.null(con)) db_save_profile(con, profile)
        if (!is.null(file_path)) save_instagram_profile(profile, file_path)

        result <- data.frame(
          username        = profile@username,
          follower_count  = profile@follower_count,
          following_count = profile@following_count,
          posts_count     = profile@posts_count,
          stringsAsFactors = FALSE
        )

        cli::cli_alert_success(
          "[{format(Sys.time(), '%H:%M:%S')}] {.val {username}}: {format(profile@follower_count, big.mark = ',')} followers"
        )
      }, error = function(e) {
        retry <<- retry + 1L
        if (retry >= max_retries) {
          cli::cli_alert_danger(
            "Failed to scrape {.val {username}} after {max_retries} attempt{?s}: {e$message}"
          )
        } else {
          cli::cli_alert_warning(
            "Attempt {retry}/{max_retries} for {.val {username}}: {e$message}"
          )
          Sys.sleep(10)
        }
      })
    }

    if (idx < length(usernames)) {
      Sys.sleep(stats::runif(1, delay_range[1], delay_range[2]))
    }

    result
  })

  profiles_data <- do.call(rbind, Filter(Negate(is.null), profiles))

  if (!is.null(file_path) && is.data.frame(profiles_data)) {
    write.csv(profiles_data, file_path, row.names = FALSE)
  }

  cli::cli_rule()
  cli::cli_alert_success("Done. {if (is.data.frame(profiles_data)) nrow(profiles_data) else 0}/{length(usernames)} profiles scraped.")

  if (is.data.frame(profiles_data) && nrow(profiles_data) > 0) profiles_data else NULL
}

#' Scrape Instagram profiles (authenticated)
#'
#' Scrapes Instagram profiles using an authenticated session, enabling access
#' to post-level data (likes, comments, dates) and higher request quotas.
#' Use a throwaway account — never your personal account.
#'
#' @param usernames Character vector of Instagram usernames.
#' @param profile_username Username of the Instagram account used for scraping.
#' @param profile_password Password of the Instagram account used for scraping.
#' @param file_path Optional path for legacy CSV output. Set to \code{NULL}
#'   to disable CSV writing.
#' @param db_path Path to the SQLite database. Set to \code{NULL} to disable.
#' @param delay_range Random inter-request delay in seconds.
#' @param max_retries Maximum retry attempts per username.
#' @return A data frame with columns \code{username}, \code{follower_count},
#'   \code{following_count}, \code{posts_count}, \code{posts_likes},
#'   \code{posts_comments}, \code{posts_dates}, or \code{NULL} on failure.
#' @export
#'
#' @examples
#' \dontrun{
#'   data <- lscrape(c("cristiano"), "dummy_account", "password123")
#' }
lscrape <- function(usernames,
                    profile_username,
                    profile_password,
                    file_path   = "data/profiles.csv",
                    db_path     = "data/rinstagram.db",
                    delay_range = c(3, 7),
                    max_retries = 3L) {
  cli::cli_h1("rinstagram scraper (authenticated)")

  login_data <- tryCatch(
    handle_login(profile_username, profile_password),
    error = function(e) {
      cli::cli_alert_danger("Login failed: {e$message}")
      NULL
    }
  )

  if (is.null(login_data)) {
    cli::cli_alert_danger("Cannot proceed without a valid session.")
    return(NULL)
  }

  cli::cli_alert_success("Logged in as {.val {profile_username}}")

  session_id <- login_data$cookies[login_data$cookies$name == "sessionid",  "value"]
  user_id    <- login_data$cookies[login_data$cookies$name == "ds_user_id", "value"]

  if (length(session_id) == 0 || is.na(session_id)) {
    cli::cli_alert_danger("No session ID found. Authentication may have failed.")
    return(NULL)
  }

  instagram_session <- new(
    "InstagramSession",
    csrf       = login_data$instagram_session@csrf,
    user_agent = login_data$instagram_session@user_agent,
    session_id = as.character(session_id),
    user_id    = as.character(user_id)
  )

  cli::cli_alert_info("Scraping {length(usernames)} profile{?s}")

  con <- if (!is.null(db_path)) db_connect(db_path) else NULL
  on.exit(if (!is.null(con)) DBI::dbDisconnect(con))

  profiles <- lapply(seq_along(usernames), function(idx) {
    username <- usernames[[idx]]
    retry    <- 0L
    result   <- NULL

    while (retry < max_retries && is.null(result)) {
      tryCatch({
        profile <- handle_graphql_request(instagram_session, username)

        if (!is.null(con)) db_save_profile(con, profile)
        if (!is.null(file_path)) save_instagram_profile(profile, file_path)

        result <- data.frame(
          username        = profile@username,
          follower_count  = profile@follower_count,
          following_count = profile@following_count,
          posts_count     = profile@posts_count,
          posts_likes     = if (length(profile@posts_likes)    > 0) paste(profile@posts_likes,    collapse = "; ") else NA_character_,
          posts_comments  = if (length(profile@posts_comments) > 0) paste(profile@posts_comments, collapse = "; ") else NA_character_,
          posts_dates     = if (length(profile@posts_dates)    > 0) paste(profile@posts_dates,    collapse = "; ") else NA_character_,
          stringsAsFactors = FALSE
        )

        cli::cli_alert_success(
          "[{format(Sys.time(), '%H:%M:%S')}] {.val {username}}: {format(profile@follower_count, big.mark = ',')} followers | {length(profile@posts_likes)} posts"
        )
      }, error = function(e) {
        retry <<- retry + 1L
        if (retry >= max_retries) {
          cli::cli_alert_danger(
            "Failed to scrape {.val {username}} after {max_retries} attempt{?s}: {e$message}"
          )
        } else {
          cli::cli_alert_warning(
            "Attempt {retry}/{max_retries} for {.val {username}}: {e$message}"
          )
          Sys.sleep(10)
        }
      })
    }

    if (idx < length(usernames)) {
      Sys.sleep(stats::runif(1, delay_range[1], delay_range[2]))
    }

    result
  })

  profiles_data <- do.call(rbind, Filter(Negate(is.null), profiles))

  if (!is.null(file_path) && is.data.frame(profiles_data)) {
    write.csv(profiles_data, file_path, row.names = FALSE)
  }

  cli::cli_rule()
  cli::cli_alert_success("Done. {if (is.data.frame(profiles_data)) nrow(profiles_data) else 0}/{length(usernames)} profiles scraped.")

  if (is.data.frame(profiles_data) && nrow(profiles_data) > 0) profiles_data else NULL
}

#' Compare and summarise scraped Instagram profile data
#'
#' Reads a CSV file or accepts a data frame and computes summary statistics
#' including average likes, average comments, follower-to-following ratio,
#' and engagement rate.
#'
#' @param source Either a file path to a CSV file (character) or a data frame
#'   from \code{scrape()} / \code{lscrape()}.
#' @param path_to_save Optional file path to write the summary CSV to.
#' @return A data frame containing the summary statistics.
#' @export
#'
#' @examples
#' \dontrun{
#'   compare("data/profiles.csv")
#'   compare("data/profiles.csv", "data/summary.csv")
#' }
compare <- function(source, path_to_save = NA) {
  if (is.character(source)) {
    if (!file.exists(source)) stop("File not found: ", source)
    data <- read_profile_csv(source)
  } else if (is.data.frame(source)) {
    data <- source
  } else {
    stop("'source' must be a file path (character) or a data frame.")
  }

  required_columns <- c("username", "follower_count", "following_count", "posts_count")
  if (!all(required_columns %in% names(data))) {
    stop("Missing columns: ", paste(setdiff(required_columns, names(data)), collapse = ", "))
  }

  data <- analyze(data)

  summary_table <- data.frame(
    Username                    = data$username,
    Follower_Count              = data$follower_count,
    Following_Count             = data$following_count,
    Posts_Count                 = data$posts_count,
    Average_Likes               = data$avg_likes,
    Average_Comments            = data$avg_comments,
    Engagement_Rate             = data$engagement_rate,
    Follower_to_Following_Ratio = data$follower_following_ratio,
    Likes_Gini                  = data$likes_gini,
    stringsAsFactors = FALSE
  )

  if (!is.na(path_to_save)) {
    write.csv(summary_table, path_to_save, row.names = FALSE)
  }

  summary_table
}

read_profile_csv <- function(file_path) {
  lines <- readLines(file_path)
  lines <- gsub("\\[", "", lines)
  lines <- gsub("\\]", "", lines)
  conn  <- textConnection(lines)
  on.exit(close(conn))
  read.csv(conn, stringsAsFactors = FALSE)
}
