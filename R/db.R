# R/db.R

#' Connect to the rinstagram SQLite database
#'
#' Opens (or creates) the SQLite database and ensures the schema is up to date.
#'
#' @param db_path Path to the SQLite file. Created automatically if it does not exist.
#' @return A DBI connection object. Remember to call \code{DBI::dbDisconnect(con)} when done.
#' @export
#'
#' @examples
#' \dontrun{
#'   con <- db_connect(tempfile(fileext = ".db"))
#'   DBI::dbDisconnect(con)
#' }
db_connect <- function(db_path = "data/rinstagram.db") {
  dir_path <- dirname(db_path)
  if (!dir.exists(dir_path)) dir.create(dir_path, recursive = TRUE)
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  db_ensure_schema(con)
  con
}

db_ensure_schema <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS profiles (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      username        TEXT    NOT NULL,
      follower_count  INTEGER,
      following_count INTEGER,
      posts_count     INTEGER,
      posts_likes     TEXT,
      posts_comments  TEXT,
      posts_dates     TEXT,
      scraped_at      TEXT    NOT NULL DEFAULT (datetime('now'))
    )
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS snapshots (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      username        TEXT    NOT NULL,
      follower_count  INTEGER,
      following_count INTEGER,
      posts_count     INTEGER,
      snapshot_date   TEXT    NOT NULL DEFAULT (date('now'))
    )
  ")

  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_profiles_username  ON profiles(username)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_profiles_scraped   ON profiles(scraped_at)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_snapshots_username ON snapshots(username)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_snapshots_date     ON snapshots(snapshot_date)")

  invisible(con)
}

#' Save an InstagramProfile to the profiles table
#'
#' @param con A DBI connection from \code{db_connect()}.
#' @param profile An \code{InstagramProfile} S4 object.
#' @export
db_save_profile <- function(con, profile) {
  DBI::dbExecute(
    con,
    "INSERT INTO profiles
       (username, follower_count, following_count, posts_count,
        posts_likes, posts_comments, posts_dates)
     VALUES (?, ?, ?, ?, ?, ?, ?)",
    list(
      profile@username,
      profile@follower_count,
      profile@following_count,
      profile@posts_count,
      if (length(profile@posts_likes) > 0)    paste(profile@posts_likes,    collapse = ";") else NA_character_,
      if (length(profile@posts_comments) > 0) paste(profile@posts_comments, collapse = ";") else NA_character_,
      if (length(profile@posts_dates) > 0)    paste(profile@posts_dates,    collapse = ";") else NA_character_
    )
  )
  invisible(profile)
}

#' Save a growth snapshot to the snapshots table
#'
#' @param con A DBI connection from \code{db_connect()}.
#' @param profile An \code{InstagramProfile} S4 object.
#' @export
db_save_snapshot <- function(con, profile) {
  DBI::dbExecute(
    con,
    "INSERT INTO snapshots (username, follower_count, following_count, posts_count)
     VALUES (?, ?, ?, ?)",
    list(
      profile@username,
      profile@follower_count,
      profile@following_count,
      profile@posts_count
    )
  )
  invisible(profile)
}

#' Load the most recent scraped profile(s) from the database
#'
#' @param con A DBI connection from \code{db_connect()}.
#' @param usernames Optional character vector of usernames to filter by.
#'   If \code{NULL} (default), all profiles are returned.
#' @return A data frame of profiles.
#' @export
db_load_profiles <- function(con, usernames = NULL) {
  if (is.null(usernames)) {
    DBI::dbGetQuery(con, "
      SELECT * FROM (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY username ORDER BY scraped_at DESC) AS rn
        FROM profiles
      ) WHERE rn = 1
    ")
  } else {
    placeholders <- paste(rep("?", length(usernames)), collapse = ", ")
    DBI::dbGetQuery(
      con,
      sprintf(
        "SELECT * FROM (
           SELECT *, ROW_NUMBER() OVER (PARTITION BY username ORDER BY scraped_at DESC) AS rn
           FROM profiles WHERE username IN (%s)
         ) WHERE rn = 1",
        placeholders
      ),
      params = as.list(usernames)
    )
  }
}

#' Get historical growth snapshots for a single profile
#'
#' @param con A DBI connection from \code{db_connect()}.
#' @param username Character. The Instagram username.
#' @return A data frame ordered by date ascending with columns
#'   \code{snapshot_date}, \code{follower_count}, \code{following_count}, \code{posts_count}.
#' @export
db_get_history <- function(con, username) {
  DBI::dbGetQuery(
    con,
    "SELECT snapshot_date, follower_count, following_count, posts_count
       FROM snapshots
      WHERE username = ?
      ORDER BY snapshot_date ASC",
    list(username)
  )
}
