# ---------------------------------------------------------------------------
# Standalone Shiny app for the nanoamp GUI.
#
# Run with:
#   shiny::runApp("02_code/gui")
# or:
#   Rscript 02_code/gui/run_gui.R
# ---------------------------------------------------------------------------

find_project_root <- function(start = getwd()) {
  p <- normalizePath(start, mustWork = FALSE)
  repeat {
    if (dir.exists(file.path(p, "02_code", "r")) || dir.exists(file.path(p, ".git"))) {
      return(p)
    }
    parent <- dirname(p)
    if (identical(parent, p)) break
    p <- parent
  }
  normalizePath(start, mustWork = FALSE)
}

project_root <- find_project_root(getwd())

source_pkg <- file.path(project_root, "02_code", "r")
if (dir.exists(source_pkg) && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(source_pkg, quiet = TRUE, export_all = FALSE)
} else if (!requireNamespace("nanoamp", quietly = TRUE)) {
  stop("Install the nanoamp R package first: R CMD INSTALL 02_code/r", call. = FALSE)
}

ui <- nanoamp:::nanoamp_gui_ui()
server <- nanoamp:::nanoamp_gui_server

shiny::shinyApp(ui = ui, server = server)
