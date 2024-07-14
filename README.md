<!-- Please be careful editing the below HTML, as GitHub is quite finicky with anything that looks like an HTML tag in GitHub Flavored Markdown. -->
<p align="center">
  <img src="assets/banner.png" alt="Banner">
</p>
<p align="center">
  <b>R package for scraping Instagram user data</b>
</p>
<p align="center">
  <a href="https://github.com/mvritz/rinstagram/blob/master/LICENSE">
    <img src="https://img.shields.io/github/license/koekeishiya/yabai.svg?color=purple" alt="License Badge">
  </a>
  <a href="https://github.com/mvrtiz/rinstagram/blob/master/CHANGELOG.md">
    <img src="https://img.shields.io/badge/view_-changelog_-purple" alt="Changelog Badge">
  </a>
  <img src="https://img.shields.io/badge/R--CMD--check_-passing_-purple" alt="Version Badge">
</p>

# rinstagram 📸

- [Introduction](#introduction)
- [Installation](#installation)
- [Usage](#usage)
    - [scrape](#scrape)
        - [Usage](#usage)
        - [Output](#output)
        - [Explanation](#explanation)
    - [lscrape](#lscrape)
        - [Usage](#usage-1)
        - [Output](#output-1)
        - [Explanation](#explanation-1)
    - [compare](#compare)
        - [Usage](#usage-2)
        - [Output](#output-2)
        - [Explanation](#explanation-2)
- [Contribution](#contribution)
- [License](#license)
- [Disclaimer](#disclaimer)

# Introduction 📝

rinstagram is an R package which allows you to work with real time Instagram data. It provides you with the ability to
scrape Instagram user data so you can analyze it in R. This package was built for my university project in Advanced
Statistical Software at _Ludwig-Maximilians-University Munich_. To read more about the motivation about this software
read [this PDF](assets/motivation.pdf).

# Installation 🖥️

You can simply install the package from github using the following command:

```R
remotes::install_github("mvritz/rinstagram")
```

# Usage 📊

The package has 2 main functions: `scrape` and `lscrape`. There is also a third function for comparing your data
called `compare`.

## scrape

### Usage

This functions allows you to get the data from a list of users without being logged in or having an API key.
You can use it like this:

```R
library(rinstagram)

users <- c("osamason", "praiseche", "cristiano")
list_of_users <- scrape(users, "data/profiles.csv")
```

The function takes 2 arguments: `users` and `output_file`.

- The `users` argument is a vector of usernames and
- the `output_file` is the optional path to the file where the data will be saved.

> Important is that instagram **ratelimits** the requests, so you should not scrape more than **10-20 users at once**.
> The
> function has a **built-in delay between requests**.

### Output

The output is a list of dataframes, where each dataframe contains the data of one user.
The data which also will be saved in the restrictive csv file looks like this:

| username  | follower_count | following_count | posts_count |
|-----------|----------------|-----------------|-------------|
| osamason  | 268735         | 435             | 4           |
| praiseche | 36436          | 234             | 2           |
| cristiano | 633484938      | 331             | 638         |

### Explanation

The function works by scraping the data from the user's profile API endpoint with a dummy CSRF Token and User-Agent.
This returns a JSON text which is parsed.
The endpoint works without using a session ID or similar. This is also
the reason why the function is limited to a small number of users at once.

## lscrape

### Usage

This function allows you to get the data from a list of users by using a session ID. That means that you have to use
your own account to scrape the data. *
*_I highly recommend using a dummy account for this and not your own account to avoid getting flagged._**
Using your own account (= scraping with a session ID) is useful if you want to scrape a lot of users at once.
You can use it like this:

```R
library(rinstagram)

users <- c("osamason", "praiseche", "cristiano")
profile_username <- "your_username"
profile_password <- "your_password"
list_of_users <- lscrape(users, profile_username, profile_password, "data/profiles.csv")
```

The function takes 4 arguments: `users`, `profile_username`, `profile_password` and `output_file`.

- The `users` argument is a vector of usernames,
- the `profile_username` is your instagram username,
- the `profile_password` is your instagram password and
- the `output_file` is the optional path to the file where the data will be saved.

### Output

Not only the number of scraped users is higher with this function the output is also more detailed during the fact that
you can now access the whole instagram API.

| username  | follower_count | following_count | posts_count | posts_likes    | posts_comments | posts_dates            |
|-----------|----------------|-----------------|-------------|----------------|----------------|------------------------|
| osamason  | 268735         | 435             | 4           | 103234; 234234 | 12493; 23423   | 2021-01-01; 2021-01-02 |
| praiseche | 36436          | 234             | 2           | 234; 234       | 234; 234       | 2021-01-01; 2021-01-02 |
| cristiano | 633484938      | 331             | 638         | 549234; 234234 | 23423; 23423   | 2021-01-01; 2021-01-02 |

### Explanation

This function is way more complex than the previous one.

#### Step 1: Password Encryption

To login the user with the Instagram API to retreive a session ID (to scrape more and more detailed data) we have to
encrypt the password.
The encryption works with a public key, a key ID and of course the password. To encrypt the password I wrote a small
Python-Encryption-API which can be found in the `src` folder (you can also find a READNE ind there where the encryption
is explained in more detail).
To get the encrypted password we have to get the public key and the key ID from the Instagram API and then send a
request to my Encryption-API.
This request returns the encrypted password which we can use to login.

#### Step 2: Login

With this encrypted password and a dummy CSRF Token and User-Agent we can login the user to the Instagram API.
This returns a JSON with your own user ID (which will be used later) and the cookies of the response of the login
request containing the session ID.

#### Step 3: Data Scraping

In the last step we can now scrape 2 endpoints (one containing the followers data and one containing the posts data)
with the session ID and our own userID for
each user in the given list. This returns a JSON which is parsed and saved in the output file.

## compare

### Usage

With this function you can compare the data of your csv file and get a summary of the data and its relations.
You can use it like this:

```R
library(rinstagram)

compare("data/profiles.csv", "data/summary.csv")
```

The function takes 2 arguments: `file_path` and `path_to_save`.

- The `file_path` is the path to the file where the data is saved.
- The `path_to_save` is the optional path to the file where the summary will be saved.

### Output

The output is a csv file with the summary of the data. The summary contains the average likes and comments per post and
the follower to following ratio.

| Username  | Follower_Count | Following_Count | Posts_Count | Average_Likes | Average_Comments | Follower_to_Following_Ratio |
|-----------|----------------|-----------------|-------------|---------------|------------------|-----------------------------|
| osamason  | 268735         | 58              | 4           | 989762        | 16352            | 4633.36206896552            |
| instagram | 674372995      | 105             | 7731        | NA            | NA               | 6422599.95238095            |

### Explanation

The function works by reading the data from the csv file and calculating the average likes and comments per post and the
follower to following ratio.

# Contribution 🤝

If you want to contribute to the package feel free to open a pull request.

# License 📜

MIT License:
https://opensource.org/licenses/MIT

# Disclaimer 🚨

This package is for educational purposes only. I am not responsible for any misuse of the package. Use at your own risk.
The package is not affiliated with Instagram or Facebook. The package is not an official API for Instagram.
