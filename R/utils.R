# R/utils.R

#' User-Agent retrieval function
#'
#' A function to retrieve a random User-Agent string
#'
#' @return A random User-Agent string
get_random_user_agent <- function() {
  user_agents <- c(
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/115.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0",
    "Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36",
    "Mozilla/5.0 (iPad; CPU OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 13_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 10; SM-A505FN) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/84.0.4147.125 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 9; SM-G960U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.157 Mobile Safari/537.36",
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:88.0) Gecko/20100101 Firefox/88.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/601.7.7 (KHTML, like Gecko) Version/9.1.2 Safari/601.7.7",
    "Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.112 Safari/537.36",
    "Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_3) AppleWebKit/537.75.14 (KHTML, like Gecko) Version/7.0.3 Safari/7046A194A",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.149 Safari/537.36"
  )

  sample(user_agents, 1)
}

#' CSRF token generation function
#'
#' A function to generate a random CSRF token for Instagram requests
#'
#' @return A random CSRF token
generate_csrf_token <- function() {
  chars <- c(letters, LETTERS, 0:9)
  paste(sample(chars, 32, replace = TRUE), collapse = "")
}


#' Save Instagram profile data to CSV
#'
#' A function to save Instagram profile data to a CSV file
#'
#' @param instagram_profile An InstagramProfile object
#' @param filePath The file path to save the data to
save_instagram_profile <- function(instagram_profile, filePath = "data/profiles.csv") {
  dirPath <- dirname(filePath)
  if (!dir.exists(dirPath)) {
    dir.create(dirPath, recursive = TRUE)
  }
  
  headers <- c("username", "follower_count", "following_count", "posts_count", "posts_likes", "posts_comments", "posts_dates")
  
  if (!file.exists(filePath)) {
    write.csv(x = setNames(data.frame(matrix(ncol = length(headers), nrow = 0)), headers), file = filePath, row.names = FALSE)
  }
  
  data <- c(
    instagram_profile@username,
    instagram_profile@follower_count,
    instagram_profile@following_count,
    instagram_profile@posts_count,
    if (length(instagram_profile@posts_likes) > 0) paste(instagram_profile@posts_likes, collapse = "; ") else NA,
    if (length(instagram_profile@posts_comments) > 0) paste(instagram_profile@posts_comments, collapse = "; ") else NA,
    if (length(instagram_profile@posts_dates) > 0) paste(instagram_profile@posts_dates, collapse = "; ") else NA
  )
  
  df <- setNames(data.frame(t(data), stringsAsFactors = FALSE), headers)
  write.table(df, file = filePath, append = TRUE, sep = ",", col.names = FALSE, row.names = FALSE, quote = TRUE)
}
