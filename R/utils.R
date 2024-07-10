# R/utils.R

#' User-Agent retrieval function
#'
#' A function to retrieve a random User-Agent string
#'
#' @return A random User-Agent string
#'
#' @examples
#' my_random_user_agent <- get_random_user_agent()
get_random_user_agent <- function() {
  user_agents <- c(
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:109.0) Gecko/20100101 Firefox/115.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:89.0) Gecko/20100101 Firefox/89.0",
    "Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.36",
    "Mozilla/5.0 (iPad; CPU OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 13_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 10; SM-A505FN) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/84.0.4147.125 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 9; SM-G960U) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.157 Mobile Safari/537.36",
    "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:88.0) Gecko/20100101 Firefox/88.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/601.7.7 (KHTML, like Gecko) Version/9.1.2 Safari/601.7.7",
    "Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.112 Safari/537.36",
    "Mozilla/5.0 (Windows NT 6.3; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/57.0.2987.133 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_9_3) AppleWebKit/537.75.14 (KHTML, like Gecko) Version/7.0.3 Safari/7046A194A",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.149 Safari/537.36"
  )

  sample(user_agents, 1)
}

#' CSRF token generation function
#'
#' A function to generate a random CSRF token for Instagram requests
#'
#' @return A random CSRF token
#'
#' @examples
#' my_csrf_token <- generate_csrf_token()
generate_csrf_token <- function() {
  chars <- c(letters, LETTERS, 0:9)
  paste(sample(chars, 32, replace = TRUE), collapse = "")
}

#' CSV saving function
#'
#' A function to save Instagram profile data to a CSV file
#'
#' @param profiles A list of InstagramProfileRaw objects
#' @param filepath The file path to save the CSV file to
#'
#' @examples
#' save_profiles_to_csv(profiles, "/path/to/data.csv")
#' save_profiles_to_csv(profiles)
save_profiles_to_csv <- function(profiles, filepath = "instagram_profiles.csv") {
  if (is.null(profiles)) {
    stop("No profiles data available to save.")
  }
  write.csv(profiles, file = filepath, row.names = FALSE)
}

encrypt_password_v10 <- function(key_id, pub_key, password) {
  # Generate a random key for encryption (XSalsa20)
  key <- random(32)

  # Generate a nonce for encryption (XSalsa20 requires 24-byte nonce)
  nonce <- random(24)

  # Encrypt the password with the nonce and key using sodium's simple_encrypt
  encrypted_password <- simple_encrypt(charToRaw(password), key, nonce)

  # Decode the hexadecimal public key into binary
  pub_key_bytes <- hex2bin(pub_key)

  # Encrypt the AES key using the public key
  encrypted_key <- crypto_box_seal(key, pub_key_bytes)

  # Construct the final encrypted payload
  encrypted <- c(as.raw(1),
                 as.raw(as.integer(key_id)),
                 as.raw(length(encrypted_key)),
                 encrypted_key,
                 nonce,
                 encrypted_password)

  # Encode the final encrypted payload in base64
  encrypted_base64 <- base64encode(encrypted)

  return(encrypted_base64)
}

encrypt_password_v10("159", "51034bde7df94d0c925f799a9297fc53eaa1369b50d09fa17bef9da2364ca328", "Rindenmulch")