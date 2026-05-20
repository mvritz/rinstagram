test_that("get_random_user_agent() returns a non-empty string", {
  ua <- rinstagram:::get_random_user_agent()
  expect_type(ua, "character")
  expect_true(nchar(ua) > 10)
})

test_that("get_random_user_agent() returns different values (probabilistic)", {
  uas <- replicate(20, rinstagram:::get_random_user_agent())
  expect_true(length(unique(uas)) > 1)
})

test_that("generate_csrf_token() returns a 32-character alphanumeric string", {
  token <- rinstagram:::generate_csrf_token()
  expect_type(token, "character")
  expect_equal(nchar(token), 32L)
  expect_true(grepl("^[A-Za-z0-9]+$", token))
})

test_that("generate_csrf_token() returns unique tokens", {
  tokens <- replicate(50, rinstagram:::generate_csrf_token())
  expect_equal(length(unique(tokens)), 50L)
})

test_that("compare() works with a data frame input", {
  data <- data.frame(
    username        = c("a", "b"),
    follower_count  = c(1000L, 2000L),
    following_count = c(100L,  200L),
    posts_count     = c(10L,   20L),
    stringsAsFactors = FALSE
  )
  result <- compare(data)
  expect_s3_class(result, "data.frame")
  expect_true("Engagement_Rate" %in% names(result))
  expect_true("Follower_to_Following_Ratio" %in% names(result))
})

test_that("compare() errors on missing file", {
  expect_error(compare("nonexistent_file.csv"), "File not found")
})
