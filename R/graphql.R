# R/graphql.R

user_id_request <- function(instagram_session, username) {
  cookies <- c(
    `csrftoken` = instagram_session$csrf,
    `ds_user_id` = instagram_session$user_id,
    `sessionid` = instagram_session$session_id
  )

  headers <- c(
    `User-Agent` = instagram_session$user_agent,
    `Accept` = "*/*",
    `Accept-Language` = "en-US,en;q=0.5",
    `Accept-Encoding` = "gzip, deflate, br",
    `X-CSRFToken` = instagram_session$csrf,
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

graphql_profile_request <- function(instagram_session, user_id) {
  variables <- sprintf('{"id":"%s","render_surface":"PROFILE"}', user_id)

  cookies <- c(
    `csrftoken` = instagram_session@csrf,
    `ds_user_id` = instagram_session@user_id,
    `sessionid` = instagram_session@session_id
  )

  headers <- c(
    `User-Agent` = instagram_session@user_agent,
    `Accept` = "*/*",
    `Accept-Language` = "en-US,en;q=0.5",
    `Accept-Encoding` = "gzip, deflate, br",
    `Content-Type` = "application/x-www-form-urlencoded",
    `X-FB-Friendly-Name` = "PolarisProfilePageContentDirectQuery",
    `X-BLOKS-VERSION-ID` = "213c82555f99bb0cecb045c627a22f08209d7a699fc238c7e73a0482e70267f9",
    `X-CSRFToken` = instagram_session@csrf,
    `X-IG-App-ID` = "936619743392459",
    `X-FB-LSD` = "qaG14T6Fg-38QVqZwrAb2J",
    `X-ASBD-ID` = "129477",
    `Origin` = "https://www.instagram.com",
    `Connection` = "keep-alive",
    `Referer` = "https://www.instagram.com/",
    `Sec-Fetch-Dest` = "empty",
    `Sec-Fetch-Mode` = "cors",
    `Sec-Fetch-Site` = "same-origin",
    `TE` = "trailers"
  )

  data <- list(
    `av` = "17841467575168557",
    `dpr` = "2",
    `jazoest` = "26234",
    `lsd` = "qaG14T6Fg-38QVqZwrAb2J",
    `fb_api_caller_class` = "RelayModern",
    `fb_api_req_friendly_name` = "PolarisProfilePageContentDirectQuery",
    `variables` = variables,
    `server_timestamps` = "true",
    `doc_id` = "7663723823674585"
  )

  res <- httr::POST(url = "https://www.instagram.com/graphql/query", httr::add_headers(.headers = headers), httr::set_cookies(.cookies = cookies), body = data, encode = "form")
  data <- jsonlite::fromJSON(httr::content(res, as = "text"))

  return(data)
}

graphql_posts_request <- function(instagram_session, username) {
  variables <- sprintf('{"data":{"count":12,"include_relationship_info":true,"latest_besties_reel_media":true,"latest_reel_media":true},"username":"%s","__relay_internal__pv__PolarisFeedShareMenurelayprovider":true}', username)

  cookies <- c(
    `csrftoken` = instagram_session@csrf,
    `ds_user_id` = instagram_session@user_id,
    `sessionid` = instagram_session@session_id
  )

  headers <- c(
    `User-Agent` = instagram_session@user_agent,
    `Accept` = "*/*",
    `Accept-Language` = "en-US,en;q=0.5",
    `Accept-Encoding` = "gzip, deflate, br",
    `Content-Type` = "application/x-www-form-urlencoded",
    `X-FB-Friendly-Name` = "PolarisProfilePostsDirectQuery",
    `X-BLOKS-VERSION-ID` = "213c82555f99bb0cecb045c627a22f08209d7a699fc238c7e73a0482e70267f9",
    `X-CSRFToken` = instagram_session@csrf,
    `X-IG-App-ID` = "936619743392459",
    `X-FB-LSD` = "AqWsT6QnaJ28PiTRAEkavo",
    `X-ASBD-ID` = "129477",
    `Origin` = "https://www.instagram.com",
    `Connection` = "keep-alive",
    `Referer` = "https://www.instagram.com/osamason/",
    `Sec-Fetch-Dest` = "empty",
    `Sec-Fetch-Mode` = "cors",
    `Sec-Fetch-Site` = "same-origin",
    `TE` = "trailers"
  )

  data <- list(
    `av` = "17841467575168557",
    `dpr` = "2",
    `jazoest` = "26055",
    `lsd` = "AqWsT6QnaJ28PiTRAEkavo",
    `fb_api_caller_class` = "RelayModern",
    `fb_api_req_friendly_name` = "PolarisProfilePostsDirectQuery",
    `variables` = variables,
    `server_timestamps` = "true",
    `doc_id` = "25816984101278502"
  )

  res <- httr::POST(url = "https://www.instagram.com/graphql/query", httr::add_headers(.headers = headers), httr::set_cookies(.cookies = cookies), body = data, encode = "form")
  data <- jsonlite::fromJSON(httr::content(res, as = "text"))

  return(data)
}

handle_graphql_request <- function(instagram_session, username) {
  user_id_data <- user_id_request(instagram_session, username)
  user_id <- user_id_data$data$user$id

  user_object_data <- graphql_profile_request(instagram_session, user_id)
  posts_data <- graphql_posts_request(instagram_session, username)

  posts_list <- lapply(posts_data$
                         data$
                         xdt_api__v1__feed__user_timeline_graphql_connection$
                         edges, function(edge) {
    likes <- edge$node$like_count
    comments <- edge$node$comment_count
    published <- as.Date(edge$node$taken_at, origin = "1970-01-01")
    list(likes = likes, comments = comments, published = published)
  })

  posts_likes <- sapply(posts_list, function(x) x$likes)
  posts_comments <- sapply(posts_list, function(x) x$comments)
  posts_dates <- sapply(posts_list, function(x) x$published)

  user_object <- new("InstagramProfile",
                     username = user_object_data$data$user$username,
                     follower_count = user_object_data$data$user$follower_count,
                     following_count = user_object_data$data$user$following_count,
                     posts_count = length(posts_list),
                     posts_likes = posts_likes,
                     posts_comments = posts_comments,
                     posts_dates = posts_dates
  )

  return(user_object)
}