# R/profile.R

#' Instagram Web Profile Request
#'
#' A function to make a request to the Instagram web profile API
#'
#' @param instagram_session An InstagramSession object containing the user agent and CSRF token
#' @param username The username of the Instagram profile to fetch
#' @return The raw JSON response from the Instagram web profile API
web_profile_request <- function(instagram_session, username) {
  cookies <- c(
    `csrftoken` = instagram_session@csrf
  )

  headers <- c(
    `User-Agent` = instagram_session@user_agent,
    `Accept` = "*/*",
    `Accept-Language` = "en-US,en;q=0.5",
    `Accept-Encoding` = "gzip, deflate, br",
    `X-CSRFToken` = instagram_session@csrf,
    `X-IG-App-ID` = "936619743392459",
    `X-ASBD-ID` = "129477",
    `X-IG-WWW-Claim` = "hmac.AR26qQ1NK_DMlx-PR_o_BNQ_OaSVyiL7y3dCxgTox0sVi_6D",
    `X-Requested-With` = "XMLHttpRequest",
    `Alt-Used` = "www.instagram.com",
    `Connection` = "keep-alive",
    `Referer` = "https://www.instagram.com/",
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
handle_web_profile_request <- function(username) {
  user_agent <- get_random_user_agent()
  csrf <- generate_csrf_token()

  instagram_session <- new("InstagramSession",
                           csrf = csrf,
                           user_agent = user_agent
  )

  data <- web_profile_request(instagram_session, username)

  user_object <- new("InstagramProfile",
                     username = data$data$user$username,
                     follower_count = data$data$user$edge_followed_by$count,
                     following_count = data$data$user$edge_follow$count,
                     posts_count = data$data$user$edge_owner_to_timeline_media$count
  )

  return(user_object)
}
