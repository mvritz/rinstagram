# R/types.R

#' InstagramProfileWebProfile Data Class
#'
#' A class to store raw Instagram profile data.
#'
#' @field username The username of the Instagram profile.
#' @field followerCount The number of followers the Instagram profile has.
#' @field followingCount The number of accounts the Instagram profile is following.
#' @field posts The number of posts the Instagram profile has.
#'
#' @examples
#' new_profile <- new("InstagramProfileWebProfile", username = "osamason", followerCount = 1000, followingCount = 100, posts = 50)
setClass(
  "InstagramProfileWebProfile",
  slots = list(
    username = "character",
    follower_count = "numeric",
    following_count = "numeric",
    posts = "numeric"
  )
)

setClass(
  "InstagramSession",
  slots = list(
    csrf = "character",
    user_agent = "character"
  )
)