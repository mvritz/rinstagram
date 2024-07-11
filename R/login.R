# R/login.R

#' Instagram Shared Data Request
#'
#' A function to make a request to the Instagram shared data API to get the encryption keys
#'
#' @param instagram_session An InstagramSession object containing the user agent and CSRF token
#' @return A list containing the shared data and the InstagramSession object
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

#' Instagram Password Encryption
#'
#' A function to encrypt a password using my custom api found in src/app/
#'
#' @param key_id The key ID for the encryption
#' @param public_key The public key for the encryption
#' @param password The password to encrypt
#' @return The encrypted password
encrypt_password_v10 <- function(key_id, public_key, password) {
  url <- "https://rinstagram-production.up.railway.app/encrypt"

  data <- list(
    key_id = key_id,
    pub_key = public_key,
    password = password
  )

  json_data <- jsonlite::toJSON(data, auto_unbox = TRUE)
  headers <- add_headers('Content-Type' = 'application/json')

  response <- httr::POST(url, body = json_data, encode = "json", config = headers)
  data <- jsonlite::fromJSON(httr::content(response, as = "text"))

  if (status_code(response) == 200) {
    return(data$encrypted)
  } else {
    stop("Error encrypting password")
  }
}

#' Instagram Login Request
#'
#' A function to make a login request to Instagram
#'
#' @param instagram_session An InstagramSession object containing the user agent and CSRF token
#' @param username The username to login with
#' @param password The password to login with
#' @param key_id The key ID for the encryption
#' @param public_key The public key for the encryption
#' @return A list containing the response data, the InstagramSession object, and the cookies
login_request <- function(instagram_session, username, password, key_id, public_key) {
  timestamp <- as.integer(Sys.time())
  encrypted_password <- encrypt_password_v10(key_id, public_key, password)
  v10_password <- sprintf("#PWD_INSTAGRAM_BROWSER:10:%d:%s", timestamp, encrypted_password)

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

  print(data)

  if (data$status != "ok") {
    stop("Error logging in")
  }

  list_to_return <- list(
    "data" = data,
    "instagram_session" = instagram_session,
    "cookies" = cookies
  )

  return(list_to_return)
}

#' Instagram Login Handler
#'
#' A function to handle a login request to Instagram
#'
#' @param username The username to login with
#' @param password The password to login with
#' @return A list containing the response data, the InstagramSession object, and the cookies
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
  return(login_data)
}
