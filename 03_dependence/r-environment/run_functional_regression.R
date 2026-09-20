# Wrapper around the package's functional regression script.
#
# The package script (02_code/r/inst/scripts/run_functional_tests.R) calls
# library() on its dependencies directly, so it needs the dedicated library
# on .libPaths() *before* it starts. This wrapper takes care of that and
# forwards every argument.
#
# Usage:
#   Rscript 03_dependence/r-environment/run_functional_regression.R \
#     --outdir 04_results/r/test_run_win --modes A,B,C --threads 4
#
# Environment variables:
#   NANOAMP_R_LIB   library directory (default: D:/tools/R/lib)

LIB <- Sys.getenv("NANOAMP_R_LIB", unset = "D:/tools/R/lib")
if (dir.exists(LIB)) .libPaths(c(LIB, .libPaths()))

find_repo_root <- function(start = getwd()) {
  p <- normalizePath(start, mustWork = FALSE)
  repeat {
    if (dir.exists(file.path(p, "01_data")) &&
        dir.exists(file.path(p, "02_code"))) {
      return(p)
    }
    parent <- dirname(p)
    if (identical(parent, p)) break
    p <- parent
  }
  normalizePath(start, mustWork = FALSE)
}

root <- find_repo_root()
script <- file.path(root, "02_code", "r", "inst", "scripts",
                    "run_functional_tests.R")
if (!file.exists(script)) stop("functional test script not found: ", script)

args <- commandArgs(trailingOnly = TRUE)
cat("repo    :", root, "\n")
cat("library :", paste(.libPaths(), collapse = " | "), "\n")
cat("script  :", script, "\n")
cat("args    :", paste(args, collapse = " "), "\n\n")

status <- system2(
  file.path(R.home("bin"), "Rscript"),
  c("--vanilla", shQuote(script), args)
)
quit(status = status)
