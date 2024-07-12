# R/functions.R

#' Scrape Instagram profiles (without session)
#'
#' A function to scrape Instagram profiles without a session. You can use this function to scrape public profiles
#' If you get rate limited, you can try using the `lscrape` function which is more robust as it is using a profile for scraping
#'
#' @param usernames A list of usernames to scrape
#' @param file_path The optional file path to save the scraped data to (default: "data/profiles.csv")
#' @return A data frame containing the scraped data (username, followers, following, post count) or NULL if an error occurred
#'
#' @export
#'
#' @examples
#' scraped_data <- scrape(c("osamason", "instagram"), "path/to/profiles.csv")
scrape <- function(usernames, file_path = "data/profiles.csv") {
  profiles <- lapply(usernames, function(username) {
    retry_count <- 0
    max_retries <- 3
    success <- FALSE
    profile <- NULL

    while (retry_count < max_retries & !success) {
      tryCatch({
        profile <- handle_web_profile_request(username)
        save_instagram_profile(profile, file_path)

        extracted_data <- data.frame(
          username = profile@username,
          follower_count = profile@follower_count,
          following_count = profile@following_count,
          posts_count = profile@posts_count
        )

        success <- TRUE
        logging_string <- sprintf("[%s] Successfully scraped user %s", format(Sys.time(), "%H:%M:%S"), username)
        cat(logging_string, "\n")

        if (username != usernames[length(usernames)]) {
          Sys.sleep(runif(1, 3, 7))
        }

        return(extracted_data)
      }, error = function(e) {
        retry_count <<- retry_count + 1
        logging_string <- sprintf("[%s] Error fetching user %s, attempt %d of %d\nError: %s",
                                  format(Sys.time(), "%H:%M:%S"), username, retry_count, max_retries, e$message)
        cat(logging_string, "\n")

        if (retry_count >= max_retries) {
          cat("\n\nError fetching user after", max_retries, "attempts:", username, "\n",
              "This might be due to rate limits. Your data is saved in the CSV file.\n",
              "You might want to try using the function `lscrape` which is more robust.\n",
              "Error: ", e$message, "\n")
          return(NULL)
        }

        Sys.sleep(10)
      })
    }

    if (success) return(profile) else return(NULL)
  })

  profiles_data <- do.call(rbind, profiles)
  if (!is.null(profiles_data)) {
    write.csv(profiles_data, file_path)
  }

  logging_string <- sprintf("[%s] Job is done. All available data has been saved to %s", format(Sys.time(), "%H:%M:%S"), file_path)
  cat(logging_string, "\n")

  return(profiles_data)
}

#' Scrape Instagram profiles (with session) [lscrape -> logged in scraping]
#'
#' A function to scrape Instagram profiles with a session
#' You need an account to use this function
#' Do NOT use your own account for scraping as it might get rate limited
#' Use a dummy account or a throwaway account
#'
#' @param usernames A list of usernames to scrape
#' @param profile_username The username of the Instagram account to use for scraping
#' @param profile_password The password of the Instagram account to use for scraping
#' @param file_path The optional file path to save the scraped data to (default: "data/profiles.csv")
#' @return A data frame containing the scraped data (username, followers, following, post count) or NULL if an error occurred
#'
#' @export
#'
#' @examples
#' scraped_data <- lscrape(c("osamason", "instagram"), "mytestaccount", "mypassword", "path/to/profiles.csv")
lscrape <- function(usernames, profile_username, profile_password, file_path) {
  login_data <- NULL

  tryCatch({
    login_data <- handle_login(profile_username, profile_password)
  }, error = function(e) {
    logging_string <- sprintf("[%s] Error during logging in. Please check your password or use another account. Error: %s", format(Sys.time(), "%H:%M:%S"), e$message)
    cat(logging_string, "\n")

    login_data <<- NULL
  })

  if (is.null(login_data)) {
    logging_string <- sprintf("[%s] Login failed or an error occurred.", format(Sys.time(), "%H:%M:%S"))
    cat(logging_string, "\n")

    return(NULL)
  } else {
    logging_string <- sprintf("[%s] Successfully logged in as %s", format(Sys.time(), "%H:%M:%S"), profile_username)
    cat(logging_string, "\n")
  }

  session_id <- ifelse("sessionid" %in% login_data$cookies$name,
                       login_data$cookies[login_data$cookies$name == "sessionid", "value"],
                       NA)

  if (is.na(session_id)) {
    logging_string <- sprintf("[%s] No session ID found during an issue with your login. Scraping is not available with this function.", format(Sys.time(), "%H:%M:%S"))
    cat(logging_string, "\n")

    return(NULL)
  }

  user_id <- ifelse("ds_user_id" %in% login_data$cookies$name,
                    login_data$cookies[login_data$cookies$name == "ds_user_id", "value"],
                    NA)

  if (is.na(user_id)) {
    logging_string <- sprintf("[%s] No user ID found during an issue with your login. Scraping is not available with this function.", format(Sys.time(), "%H:%M:%S"))
    cat(logging_string, "\n")

    return(NULL)
  }

  instagram_session <- new("InstagramSession",
                           csrf = login_data$instagram_session@csrf,
                           user_agent = login_data$instagram_session@user_agent,
                           session_id = session_id,
                           user_id = user_id
  )

  profiles <- lapply(usernames, function(username) {
    retry_count <- 0
    max_retries <- 3
    success <- FALSE

    while (retry_count < max_retries) {
      tryCatch({
        profile <- handle_graphql_request(instagram_session, username)
        save_instagram_profile(profile, file_path)

        extracted_data <- data.frame(
          username = profile@username,
          follower_count = profile@follower_count,
          following_count = profile@following_count,
          posts_count = profile@posts_count,
          posts_likes = if (length(profile@posts_likes) > 0) paste(profile@posts_likes, collapse = "; ") else NA,
          posts_comments = if (length(profile@posts_comments) > 0) paste(profile@posts_comments, collapse = "; ") else NA,
          posts_dates = if (length(profile@posts_dates) > 0) paste(profile@posts_dates, collapse = "; ") else NA
        )

        success <- TRUE

        logging_string <- sprintf("[%s] Successfully scraped user %s", format(Sys.time(), "%H:%M:%S"), username)
        cat(logging_string, "\n")

        if (username != usernames[length(usernames)]) {
          Sys.sleep(runif(1, 3, 7))
        }

        return(extracted_data)
      }, error = function(e) {
        retry_count <- retry_count + 1
        if (retry_count == max_retries) {
          cat("\n\n Error fetching user after", max_retries, "attempts:", username, "\n",
              "This might be due to rate limits. Your data is saved in the CSV file.\n",
              "You might want to try using the function `lscrape` which is more robust.\n",
              "Error: ", e$message, "\n")

          write.csv(profiles, file_path)
          return(NULL)
        }

        logging_string <- sprintf("[%s] Error fetching user %s, attempt %d of %d", format(Sys.time(), "%H:%M:%S"), username, retry_count, max_retries)
        cat(logging_string, "\n",
            format(Sys.time(), "%H:%M:%S"), "Error: ", e$message, "\n")

        Sys.sleep(10)
      })
    }

    if (!success) NULL
  })

  profiles_data <- do.call(rbind, profiles)
  if (is.data.frame(profiles_data)) write.csv(profiles_data, file_path)

  logging_string <- sprintf("[%s] Job is done. All available data has been saved to %s", format(Sys.time(), "%H:%M:%S"), file_path)
  cat(logging_string, "\n")
  return(profiles_data)
}

#' Compare Instagram profile data
#'
#' A function to compare Instagram profile data from a CSV file
#'
#' @param file_path The file path to the CSV file
#' @param path_to_save The optional file path to save the summary data to
#' @return A data frame containing the summary of the data
#'
#' @export
#'
#' @examples
#' instagram_data_comparison <- compare("path_to_your_instagram_data.csv")
#' instagram_data_comparison <- compare("path_to_your_instagram_data.csv", "path_to_save_summary.csv")
compare <- function(file_path, path_to_save = NA) {
  if (!file.exists(file_path)) {
    stop("File does not exist.")
  }

  read_custom_csv <- function(file_path) {
    lines <- readLines(file_path)
    lines <- gsub("\\[", "", lines)
    lines <- gsub("\\]", "", lines)
    textConnection(lines) -> conn
    data <- read.csv(conn, stringsAsFactors = FALSE)
    close(conn)
    return(data)
  }

  data <- read_custom_csv(file_path)

  required_columns <- c("username", "follower_count", "following_count", "posts_count")
  if (!all(required_columns %in% names(data))) {
    stop("CSV file does not contain all required columns.")
  }

  if (is.character(data$posts_likes[1])) {
    data$posts_likes <- lapply(data$posts_likes, function(x) if (!is.na(x)) eval(parse(text = x)) else NA)
    data$posts_comments <- lapply(data$posts_comments, function(x) if (!is.na(x)) eval(parse(text = x)) else NA)
  }

  data$avg_likes <- sapply(data$posts_likes, function(x) if (is.na(x)) NA else mean(x, na.rm = TRUE))
  data$avg_comments <- sapply(data$posts_comments, function(x) if (is.na(x)) NA else mean(x, na.rm = TRUE))

  data$follower_to_following_ratio <- with(data, follower_count / following_count)

  summary_table <- data.frame(
    Username = data$username,
    Follower_Count = data$follower_count,
    Following_Count = data$following_count,
    Posts_Count = data$posts_count,
    Average_Likes = data$avg_likes,
    Average_Comments = data$avg_comments,
    Follower_to_Following_Ratio = data$follower_to_following_ratio
  )

  if (!is.na(path_to_save)) {
    write.csv(summary_table, path_to_save, row.names = FALSE)
  }

  return(summary_table)
}
