test_that("db_connect() creates database and schema", {
  tmp <- withr::local_tempfile(fileext = ".db")
  con <- db_connect(tmp)
  on.exit(DBI::dbDisconnect(con))

  tables <- DBI::dbListTables(con)
  expect_true("profiles"  %in% tables)
  expect_true("snapshots" %in% tables)
})

test_that("db_save_profile() persists a profile", {
  tmp <- withr::local_tempfile(fileext = ".db")
  con <- db_connect(tmp)
  on.exit(DBI::dbDisconnect(con))

  profile <- new(
    "InstagramProfile",
    username        = "testuser",
    follower_count  = 1000,
    following_count = 200,
    posts_count     = 50
  )
  db_save_profile(con, profile)

  rows <- DBI::dbGetQuery(con, "SELECT * FROM profiles WHERE username = 'testuser'")
  expect_equal(nrow(rows), 1L)
  expect_equal(rows$follower_count, 1000L)
})

test_that("db_save_snapshot() and db_get_history() round-trip correctly", {
  tmp <- withr::local_tempfile(fileext = ".db")
  con <- db_connect(tmp)
  on.exit(DBI::dbDisconnect(con))

  profile <- new("InstagramProfile",
                 username = "tracker", follower_count = 5000,
                 following_count = 300, posts_count = 20)
  db_save_snapshot(con, profile)

  history <- db_get_history(con, "tracker")
  expect_equal(nrow(history), 1L)
  expect_equal(history$follower_count, 5000L)
  expect_true("snapshot_date" %in% names(history))
})

test_that("db_load_profiles() returns only the latest profile per user", {
  tmp <- withr::local_tempfile(fileext = ".db")
  con <- db_connect(tmp)
  on.exit(DBI::dbDisconnect(con))

  profile_v1 <- new("InstagramProfile", username = "user1", follower_count = 100, following_count = 10, posts_count = 5)
  profile_v2 <- new("InstagramProfile", username = "user1", follower_count = 200, following_count = 10, posts_count = 5)
  db_save_profile(con, profile_v1)
  Sys.sleep(1)
  db_save_profile(con, profile_v2)

  result <- db_load_profiles(con, "user1")
  expect_equal(nrow(result), 1L)
  expect_equal(result$follower_count, 200L)
})

test_that("db_load_profiles() filters by username", {
  tmp <- withr::local_tempfile(fileext = ".db")
  con <- db_connect(tmp)
  on.exit(DBI::dbDisconnect(con))

  for (u in c("alice", "bob", "charlie")) {
    p <- new("InstagramProfile", username = u, follower_count = 100, following_count = 10, posts_count = 5)
    db_save_profile(con, p)
  }

  result <- db_load_profiles(con, c("alice", "charlie"))
  expect_equal(nrow(result), 2L)
  expect_setequal(result$username, c("alice", "charlie"))
})
