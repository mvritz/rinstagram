# R/shiny.R

#' Launch the rinstagram Shiny dashboard
#'
#' Opens an interactive analytics dashboard in your browser or RStudio viewer.
#' The dashboard connects to the local SQLite database and, when available,
#' to the ML microservice for live predictions.
#'
#' @param db_path Path to the SQLite database (default: \code{"data/rinstagram.db"}).
#' @param ml_url  Base URL of the ML microservice. Defaults to the
#'   \code{RINSTAGRAM_ML_URL} environment variable or \code{http://localhost:8001}.
#' @param ... Additional arguments passed to \code{shiny::runApp()}.
#' @return Called for its side effect (launches the Shiny app).
#' @export
#'
#' @examples
#' \dontrun{
#'   launch_dashboard()
#' }
launch_dashboard <- function(db_path = "data/rinstagram.db",
                              ml_url  = Sys.getenv("RINSTAGRAM_ML_URL", "http://localhost:8001"),
                              ...) {
  if (!requireNamespace("shiny",           quietly = TRUE)) stop("Package 'shiny' is required. Install with: install.packages('shiny')")
  if (!requireNamespace("shinydashboard",  quietly = TRUE)) stop("Package 'shinydashboard' is required. Install with: install.packages('shinydashboard')")
  if (!requireNamespace("DT",              quietly = TRUE)) stop("Package 'DT' is required. Install with: install.packages('DT')")

  app_dir <- system.file("shiny", package = "rinstagram")
  if (!nzchar(app_dir) || !dir.exists(app_dir)) {
    stop("Shiny app directory not found. Reinstall the package.")
  }

  Sys.setenv(RINSTAGRAM_DB_PATH = db_path)
  Sys.setenv(RINSTAGRAM_ML_URL  = ml_url)

  shiny::runApp(app_dir, ...)
}
