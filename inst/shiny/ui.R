library(shiny)
library(shinydashboard)
library(plotly)
library(DT)

dashboardPage(
  skin = "purple",

  dashboardHeader(
    title = tags$span(
      tags$img(src = "https://img.icons8.com/fluency/24/instagram-new.png", style = "margin-right:6px;"),
      "rinstagram"
    ),
    titleWidth = 220
  ),

  dashboardSidebar(
    width = 220,
    sidebarMenu(
      id = "tabs",
      menuItem("Profile Explorer", tabName = "explorer",  icon = icon("search")),
      menuItem("Growth Tracker",   tabName = "growth",    icon = icon("chart-line")),
      menuItem("Comparison",       tabName = "compare",   icon = icon("chart-pie")),
      menuItem("Leaderboard",      tabName = "leaderboard", icon = icon("trophy")),
      menuItem("Bot Detector",     tabName = "bots",      icon = icon("robot"))
    ),
    hr(),
    tags$div(
      style = "padding: 10px 15px; font-size: 11px; color: #aaa;",
      tags$p(icon("database"), "DB:", textOutput("db_status", inline = TRUE)),
      tags$p(icon("brain"),    "ML:", textOutput("ml_status", inline = TRUE))
    )
  ),

  dashboardBody(
    tags$head(
      tags$style(HTML("
        .content-wrapper, .right-side { background-color: #f4f6f8; }
        .box { border-top-color: #833AB4; }
        .small-box.bg-purple { background-color: #833AB4 !important; }
        .small-box.bg-blue   { background-color: #405DE6 !important; }
        .small-box.bg-red    { background-color: #E1306C !important; }
        .small-box.bg-yellow { background-color: #FCAF45 !important; color: #333 !important; }
      "))
    ),

    tabItems(

      # ── Profile Explorer ──────────────────────────────────────────────────
      tabItem(
        tabName = "explorer",
        fluidRow(
          box(
            width = 12, title = "Search Profile", status = "primary", solidHeader = TRUE,
            fluidRow(
              column(4, textInput("explorer_username", "Instagram Username", placeholder = "e.g. cristiano")),
              column(2, br(), actionButton("explorer_go", "Analyse", class = "btn-primary btn-block", icon = icon("search")))
            )
          )
        ),
        fluidRow(
          valueBoxOutput("vb_followers",  width = 3),
          valueBoxOutput("vb_following",  width = 3),
          valueBoxOutput("vb_posts",      width = 3),
          valueBoxOutput("vb_engagement", width = 3)
        ),
        fluidRow(
          box(width = 6, title = "ML: Engagement Prediction", status = "warning", solidHeader = TRUE,
              plotlyOutput("explorer_engagement_gauge", height = "250px")),
          box(width = 6, title = "ML: Bot Risk Score",         status = "danger",  solidHeader = TRUE,
              plotlyOutput("explorer_bot_gauge",        height = "250px"))
        ),
        fluidRow(
          box(width = 12, title = "ML: Content Niche",          status = "success", solidHeader = TRUE,
              uiOutput("explorer_niche"))
        )
      ),

      # ── Growth Tracker ────────────────────────────────────────────────────
      tabItem(
        tabName = "growth",
        fluidRow(
          box(
            width = 12, title = "Growth Tracker", status = "primary", solidHeader = TRUE,
            fluidRow(
              column(4, selectInput("growth_username", "Profile", choices = NULL)),
              column(3, selectInput("growth_horizon",  "Forecast Horizon",
                                   choices = c("30 days" = 30, "60 days" = 60, "90 days" = 90))),
              column(3, br(), checkboxInput("growth_forecast_on", "Show LSTM Forecast", value = TRUE)),
              column(2, br(), actionButton("growth_go", "Update", class = "btn-primary btn-block", icon = icon("sync")))
            )
          )
        ),
        fluidRow(
          box(width = 12, title = "Follower Growth", status = "info", solidHeader = TRUE,
              plotlyOutput("growth_chart", height = "420px"))
        ),
        fluidRow(
          valueBoxOutput("growth_vb_current",    width = 4),
          valueBoxOutput("growth_vb_change",     width = 4),
          valueBoxOutput("growth_vb_forecast90", width = 4)
        )
      ),

      # ── Comparison ────────────────────────────────────────────────────────
      tabItem(
        tabName = "compare",
        fluidRow(
          box(
            width = 12, title = "Compare Profiles", status = "primary", solidHeader = TRUE,
            fluidRow(
              column(8, selectizeInput("compare_usernames", "Select Profiles",
                                       choices = NULL, multiple = TRUE,
                                       options = list(placeholder = "Select up to 10 profiles"))),
              column(4, br(), actionButton("compare_go", "Compare", class = "btn-primary btn-block", icon = icon("chart-pie")))
            )
          )
        ),
        fluidRow(
          box(width = 6, title = "Radar Comparison",            status = "warning", solidHeader = TRUE,
              plotlyOutput("compare_radar",   height = "400px")),
          box(width = 6, title = "Engagement Rate Distribution", status = "warning", solidHeader = TRUE,
              plotlyOutput("compare_engagement", height = "400px"))
        )
      ),

      # ── Leaderboard ───────────────────────────────────────────────────────
      tabItem(
        tabName = "leaderboard",
        fluidRow(
          box(
            width = 12, title = "Leaderboard", status = "primary", solidHeader = TRUE,
            fluidRow(
              column(4, selectInput("lb_sort_by", "Sort By",
                                   choices = c("Engagement Rate" = "engagement_rate",
                                               "Followers"       = "follower_count",
                                               "Posts"           = "posts_count",
                                               "Avg Likes"       = "avg_likes"))),
              column(2, br(), actionButton("lb_refresh", "Refresh", class = "btn-default btn-block", icon = icon("sync")))
            )
          )
        ),
        fluidRow(
          box(width = 12, title = NULL,
              DTOutput("leaderboard_table"))
        )
      ),

      # ── Bot Detector ──────────────────────────────────────────────────────
      tabItem(
        tabName = "bots",
        fluidRow(
          box(
            width = 12, title = "Bot / Fake Account Detector", status = "danger", solidHeader = TRUE,
            fluidRow(
              column(8, selectizeInput("bot_usernames", "Select Profiles",
                                       choices = NULL, multiple = TRUE,
                                       options = list(placeholder = "Select profiles to analyse"))),
              column(4, br(), actionButton("bot_go", "Detect", class = "btn-danger btn-block", icon = icon("robot")))
            )
          )
        ),
        fluidRow(
          box(width = 7, title = "Bot Risk Chart", status = "danger", solidHeader = TRUE,
              plotlyOutput("bot_chart", height = "400px")),
          box(width = 5, title = "Results Table",  status = "danger", solidHeader = TRUE,
              DTOutput("bot_table"))
        )
      )
    )
  )
)
