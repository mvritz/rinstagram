source("R/utils.R")
source("R/types.R")

shared_data_request <- function(instagram_session) {
  cookies <- c(
    `csrftoken` = instagram_session@csrf
  )

  headers <- c(
    `User-Agent` = instagram_session@user_agent,
    `Accept` = "*/*",
    `Accept-Language` = "en-US,en;q=0.5",
    `Accept-Encoding` = "gzip, deflate, br",
    `X-CSRFToken` = instagram_session@csrf,
    `X-Instagram-AJAX` = "1014781394",
    `X-IG-App-ID` = "936619743392459",
    `X-ASBD-ID` = "129477",
    `X-IG-WWW-Claim` = "0",
    `Content-Type` = "application/x-www-form-urlencoded",
    `X-Requested-With` = "XMLHttpRequest",
    `Origin` = "https://www.instagram.com",
    `Alt-Used` = "www.instagram.com",
    `Connection` = "keep-alive",
    `Referer` = "https://www.instagram.com/",
    `Sec-Fetch-Dest` = "empty",
    `Sec-Fetch-Mode` = "cors",
    `Sec-Fetch-Site` = "same-origin",
    `TE` = "trailers"
  )

  url <- "https://www.instagram.com/data/shared_data/"

  res <- httr::GET(url = url, httr::add_headers(.headers = headers), httr::set_cookies(.cookies = cookies))
  data <- jsonlite::fromJSON(httr::content(res, as = "text"))

  list_to_return <- list(
    "data" = data,
    "instagram_session" = instagram_session
  )

  return(list_to_return)
}

login_request <- function(instagram_session, username, password, key_id, public_key) {
  timestamp <- as.integer(Sys.time())
  print(key_id)
  print(public_key)
  print(password)
  encrypted_password <- encrypt_password_v10(key_id, public_key, password)
  v10_password <- "#PWD_INSTAGRAM_BROWSER:10" +
    ":" +
    timestamp +
    ":" +
    encrypted_password

  cookies <- c(
    `csrftoken` = instagram_session@csrf
  )

  headers <- c(
    `User-Agent` = instagram_session@user_agent,
    `Accept` = "*/*",
    `Accept-Language` = "en-US,en;q=0.5",
    `Accept-Encoding` = "gzip, deflate, br",
    `X-CSRFToken` = csrf,
    `X-Instagram-AJAX` = "1014781394",
    `X-IG-App-ID` = "936619743392459",
    `X-ASBD-ID` = "129477",
    `X-IG-WWW-Claim` = "0",
    `Content-Type` = "application/x-www-form-urlencoded",
    `X-Requested-With` = "XMLHttpRequest",
    `Origin` = "https://www.instagram.com",
    `Alt-Used` = "www.instagram.com",
    `Connection` = "keep-alive",
    `Referer` = "https://www.instagram.com/",
    `Sec-Fetch-Dest` = "empty",
    `Sec-Fetch-Mode` = "cors",
    `Sec-Fetch-Site` = "same-origin",
    `TE` = "trailers"
  )

  data <- list(
    `enc_password` = v10_password,
    `optIntoOneTap` = "false",
    `queryParams` = "{}",
    `trustedDeviceRecords` = "{}",
    `username` = username
  )

  res <- httr::POST(url = "https://www.instagram.com/api/v1/web/accounts/login/ajax/", httr::add_headers(.headers = headers), httr::set_cookies(.cookies = cookies), body = data, encode = "form")
  data <- jsonlite::fromJSON(httr::content(res, as = "text"))
  cookies <- httr::cookies(res)

  list_to_return <- list(
    "data" = data,
    "instagram_session" = instagram_session,
    "cookies" = cookies
  )

  return(list_to_return)
}

handle_login <- function(username, password) {
  user_agent <- get_random_user_agent()
  csrf <- generate_csrf_token()

  instagram_session <- new("InstagramSession",
                           csrf = csrf,
                           user_agent = user_agent
  )

  shared_data <- shared_data_request(instagram_session)
  instagram_session <- shared_data$instagram_session
  data <- shared_data$data

  key_id <- data$encryption$key_id
  public_key <- data$encryption$public_key

  login_data <- login_request(instagram_session, username, password, key_id, public_key)
}

handle_login("mo.drs", "Rindenmulch2004")