# Run the nanoamp testthat suite against the installed package.
#
# Usage:
#   Rscript 03_dependence/r-environment/run_tests.R
#
# Environment variables:
#   NANOAMP_R_LIB   library directory (default: D:/tools/R/lib)
#   NANOAMP_REPO    repository root  (default: auto-detected)

LIB <- Sys.getenv("NANOAMP_R_LIB", unset = "D:/tools/R/lib")
if (dir.exists(LIB)) .libPaths(c(LIB, .libPaths()))
options(
  repos = c(CRAN = "https://mirrors.tuna.tsinghua.edu.cn/CRAN/"),
  download.file.method = "libcurl",
  Ncpus = max(1L, parallel::detectCores() - 1L)
)

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

root <- Sys.getenv("NANOAMP_REPO", unset = "")
if (!nzchar(root)) root <- find_repo_root()

cat("repo      :", root, "\n")
cat("R         :", R.version.string, "\n")
cat("library   :", paste(.libPaths(), collapse = " | "), "\n")

suppressPackageStartupMessages(library(nanoamp))
cat("nanoamp   :", as.character(packageVersion("nanoamp")), "\n")
cat("platform  :", nanoamp:::nanoamp_platform(), "\n")

mp <- nanoamp:::nanoamp_tool_path("minimap2", required = FALSE)
cat("minimap2  :", if (is.null(mp)) "<not found>" else mp, "\n")
if (!is.null(mp)) {
  cat("  version :", nanoamp:::nanoamp_tool_version("minimap2"), "\n")
}
cat("r aligner :", nanoamp:::pa_provider_name(), "\n\n")

res <- testthat::test_dir(
  file.path(root, "02_code", "r", "tests", "testthat"),
  package = "nanoamp",
  reporter = "summary",
  stop_on_failure = FALSE
)
df <- as.data.frame(res)
cat("\n=== totals ===\n")
cat("files    :", length(unique(df$file)), "\n")
cat("tests    :", nrow(df), "\n")
cat("passed   :", sum(df$passed), "\n")
cat("failed   :", sum(df$failed), "\n")
cat("errors   :", sum(df$error), "\n")
cat("skipped  :", sum(df$skipped), "\n")
cat("warnings :", sum(df$warning), "\n")

if (sum(df$failed) + sum(df$error) > 0) {
  cat("\n=== failing tests ===\n")
  print(df[df$failed > 0 | df$error, c("file", "test")])
  quit(status = 1)
}
cat("\nALL TESTS PASSED\n")
