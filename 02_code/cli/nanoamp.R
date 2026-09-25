#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# Standalone nanoamp CLI entry point.
#
# It uses the installed nanoamp R package when available. During development,
# it can load the source package directly from 02_code with pkgload.
# ---------------------------------------------------------------------------

find_project_root <- function(start = getwd()) {
  p <- normalizePath(start, mustWork = FALSE)
  repeat {
    # 02_code/ is both the repository code root and the R package root
    # (DESCRIPTION / R / tests / inst live directly in it).
    if (file.exists(file.path(p, "DESCRIPTION")) && dir.exists(file.path(p, "R"))) {
      return(p)
    }
    if (dir.exists(file.path(p, ".git"))) return(p)
    parent <- dirname(p)
    if (identical(parent, p)) break
    p <- parent
  }
  normalizePath(start, mustWork = FALSE)
}

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[1]) else NA_character_
start_dir <- if (!is.na(script_path)) dirname(script_path) else getwd()
project_root <- find_project_root(start_dir)

# From the repository, nanoamp.R sits in 02_code/cli/ and the package root is
# its parent; from an installed copy it is already inside the package.
source_pkg <- if (file.exists(file.path(project_root, "DESCRIPTION"))) {
  project_root
} else {
  file.path(project_root, "02_code")
}
if (dir.exists(source_pkg) && requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(source_pkg, quiet = TRUE, export_all = FALSE)
  nanoamp::nanoamp_cli()
} else if (requireNamespace("nanoamp", quietly = TRUE)) {
  nanoamp::nanoamp_cli()
} else {
  stop(
    "The nanoamp R package is not installed.\n",
    "Install it with: R CMD INSTALL 02_code",
    call. = FALSE
  )
}
