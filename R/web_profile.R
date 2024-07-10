# R/web_profile.R
source("R/utils.R")
source("R/types.R")

#' Instagram Web Profile Request
#'
#' A function to make a request to the Instagram web profile API
#'
#' @param csrf The CSRF token to use in the request
#' @param user_agent The User-Agent string to use in the request
#' @param username The username of the Instagram profile to fetch
#' @return The raw JSON response from the Instagram web profile API
#'
#' @examples
#' data <- web_profile_request("AoH9uiQnUrg0tfceSN9dYbphGEQN6N59", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/115.0", "osamason")
web_profile_request <- function(csrf, user_agent, username) {
  cookies <- c(
    `csrftoken` = csrf
  )

  headers <- c(
    `User-Agent` = user_agent,
    `Accept` = "*/*",
    `Accept-Language` = "en-US,en;q=0.5",
    `Accept-Encoding` = "gzip, deflate, br",
    `X-CSRFToken` = csrf,
    `X-IG-App-ID` = "936619743392459",
    `X-ASBD-ID` = "129477",
    `X-IG-WWW-Claim` = "hmac.AR26qQ1NK_DMlx-PR_o_BNQ_OaSVyiL7y3dCxgTox0sVi_6D",
    `X-Requested-With` = "XMLHttpRequest",
    `Alt-Used` = "www.instagram.com",
    `Connection` = "keep-alive",
    `Referer` = "https://www.instagram.com/osamason/",
    `Sec-Fetch-Dest` = "empty",
    `Sec-Fetch-Mode` = "cors",
    `Sec-Fetch-Site` = "same-origin",
    `TE` = "trailers"
  )

  params <- list(
    `username` = username
  )

  url <- "https://www.instagram.com/api/v1/users/web_profile_info/"

  res <- httr::GET(url = url, httr::add_headers(.headers = headers), query = params, httr::set_cookies(.cookies = cookies))
  data <- jsonlite::fromJSON(httr::content(res, as = "text"))

  return(data)
}

#' Instagram Web Profile Request Handler
#'
#' A function to handle a web profile request for a given Instagram profile
#'
#' @param username The username of the Instagram profile to fetch
#' @return An InstagramProfileWebProfile object
#'
#' @examples
#' osamason_user_object <- handle_web_profile_request("osamason")
handle_web_profile_request <- function(username) {
  user_agent <- get_random_user_agent()
  csrf <- generate_csrf_token()

  data <- web_profile_request(csrf, user_agent, username)

  user_object <- new("InstagramProfileWebProfile",
                     username = data$data$user$username,
                     followerCount = data$data$user$edge_followed_by$count,
                     followingCount = data$data$user$edge_follow$count,
                     posts = data$data$user$edge_owner_to_timeline_media$count
  )

  return(user_object)
}

#' Instagram Web Profile Request Handler
#'
#' A function to handle multiple web profile requests for a list of Instagram profiles
#'
#' @param usernames A list of usernames to fetch
#' @return A list of InstagramProfileWebProfile objects
#'
#' @examples
#' user_objects <- handle_web_profile_requests(c("osamason", "instagram"))
handle_web_profile_requests <- function(usernames) {
  profiles <- lapply(usernames, function(username) {
    Sys.sleep(runif(1, 2, 5))
    tryCatch({
      handle_web_profile_request(username)
    }, error = function(e) {
      cat("Error fetching user:", username, "\n", e)
      NULL
    })
  })

  do.call(rbind, profiles)
}
