test_that("analyze() enriches a basic data frame", {
  data <- data.frame(
    username        = c("user_a", "user_b"),
    follower_count  = c(10000L, 500L),
    following_count = c(500L,  1000L),
    posts_count     = c(50L,    10L),
    stringsAsFactors = FALSE
  )
  result <- analyze(data)

  expect_s3_class(result, "data.frame")
  expect_true(all(c("engagement_rate", "follower_following_ratio", "likes_gini") %in% names(result)))
  expect_equal(result$follower_following_ratio, c(20, 0.5))
  expect_true(all(is.na(result$engagement_rate)))
})

test_that("analyze() computes engagement_rate when post data is present", {
  data <- data.frame(
    username        = "user_a",
    follower_count  = 10000L,
    following_count = 500L,
    posts_count     = 3L,
    posts_likes     = "100;200;300",
    posts_comments  = "10;20;30",
    stringsAsFactors = FALSE
  )
  result <- analyze(data)

  expect_equal(result$avg_likes,    200, tolerance = 1e-6)
  expect_equal(result$avg_comments,  20, tolerance = 1e-6)
  expect_equal(result$engagement_rate, (200 + 20) / 10000, tolerance = 1e-6)
})

test_that("analyze() errors on missing required columns", {
  expect_error(analyze(data.frame(username = "x")), "Missing required columns")
})

test_that("analyze() errors on non-data-frame input", {
  expect_error(analyze(list(a = 1)), "'data' must be a data frame")
})

test_that("compute_gini returns NA for single-element vector", {
  result <- rinstagram:::compute_gini(c(100))
  expect_true(is.na(result))
})

test_that("compute_gini returns 0 for uniform distribution", {
  result <- rinstagram:::compute_gini(c(100, 100, 100))
  expect_equal(result, 0, tolerance = 1e-6)
})

test_that("compute_engagement_rate handles zero follower count", {
  result <- rinstagram:::compute_engagement_rate(100, 10, 0)
  expect_true(is.na(result))
})
