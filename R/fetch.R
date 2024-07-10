rawProfileRequest <- function(csrf, userAgent, username) {
  cookies <- c(
    `csrftoken` = csrf
  )

  headers <- c(
    `User-Agent` = userAgent,
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

  res <- httr::GET(url = "https://www.instagram.com/api/v1/users/web_profile_info/", httr::add_headers(.headers = headers), query = params, httr::set_cookies(.cookies = cookies))
  data <- jsonlite::fromJSON(httr::content(res, as = "text"))

  return(data)
}

fetchRawAccount <- function(username) {
  userAgent <- getRandomUserAgent()
  csrf <- generate_csrf_token()

  data <- rawProfileRequest(csrf, userAgent, username)

  userObject <- new("InstagramProfileRaw",
                    username = data$data$user$username,
                    followerCount = data$data$user$edge_followed_by$count,
                    followingCount = data$data$user$edge_follow$count,
                    posts = data$data$user$edge_owner_to_timeline_media$count
  )

  return(userObject)
}

fetchMultipleRawAccounts <- function(usernames) {
  profiles <- lapply(usernames, function(username) {
    Sys.sleep(runif(1, 2, 5))
    tryCatch({
      fetchRawAccount(username)
    }, error = function(e) {
      cat("Error fetching user:", username, "\n", e)
      NULL
    })
  })

  do.call(rbind, profiles)
}