# R/types.R

#' InstagramProfile Data Class
#'
#' A class to store Instagram profile data
#'
#' @field username The username of the Instagram profile
#' @field followerCount The number of followers the Instagram profile has
#' @field followingCount The number of accounts the Instagram profile is following
#' @field posts_count The number of posts the Instagram profile has
#' @field posts_likes A optional list of the number of likes each post has
#' @field posts_comments A optional list of the number of comments each post has
#' @field posts_dates A optional list of the dates each post was posted
setClass(
  "InstagramProfile",
  slots = list(
    username = "character",
    follower_count = "numeric",
    following_count = "numeric",
    posts_count = "numeric",
    posts_likes = "list",
    posts_comments = "list",
    posts_dates = "list"
  ),
  prototype = list(
    posts_likes = list(),
    posts_comments = list(),
    posts_dates = list()
  )
)

  #' InstagramSession Data Class
  #'
  #' A class to store Instagram session data
  #'
  #' @field csrf The CSRF token for the session
  #' @field user_agent The User-Agent string for the session
  #' @field session_id The session ID for the session (optional)
  #' @field user_id The user ID for the session (optional)
setClass(
  "InstagramSession",
  slots = list(
    csrf = "character",
    user_agent = "character",
    session_id = "character",
    user_id = "character"
  ),
  prototype = list(
    session_id = NA_character_,
    user_id = NA_character_
  )
)