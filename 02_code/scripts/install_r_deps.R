#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# Install the R dependencies of nanoamp.
#
# Order of preference:
#   1. pak::pak()          -- resolves the full dependency graph and uses the
#                             precompiled CRAN / Bioconductor binaries for the
#                             current platform when they exist (macOS arm64,
#                             macOS x86_64 and Windows have them), so it is
#                             usually much faster than installing from source;
#   2. install.packages()  -- plain CRAN install for the CRAN part;
#      BiocManager::install() -- the Bioconductor part.
#
# Usage:
#   Rscript 02_code/scripts/install_r_deps.R
#   Rscript 02_code/scripts/install_r_deps.R --only-required
#   Rscript 02_code/scripts/install_r_deps.R --dry-run
# ---------------------------------------------------------------------------

args <- commandArgs(trailingOnly = TRUE)
dry_run <- "--dry-run" %in% args
only_required <- "--only-required" %in% args

# Required to run nanoamp; optional adds Mode B clustering/consensus quality and
# the pwalign provider used by pairwiseAlignment() on Bioconductor >= 3.19.
# ShortRead is deliberately not listed: FASTQ is read by the base-R parser in
# R/io.R, and ShortRead would drag pwalign into every installation.
required <- c(
  "Biostrings", "IRanges", "Matrix", "Rsamtools",
  "data.table", "jsonlite", "optparse", "readxl"
)
optional <- c("DECIPHER", "pwalign")

# Provided by the R installation itself; listed only so pak does not try to
# install them again.
base_pkgs <- rownames(installed.packages(priority = "base"))

targets <- if (only_required) required else c(required, optional)

log_step <- function(...) cat(sprintf("==> %s\n", paste0(...)))

missing <- function(pkgs) {
  pkgs[!vapply(pkgs, function(p) requireNamespace(p, quietly = TRUE), logical(1))]
}

log_step("R ", R.version.string, " (", R.version$platform, ")")

# The repository itself is installed separately with R CMD INSTALL 02_code; this
# script only handles its dependencies.
need <- setdiff(missing(targets), base_pkgs)
if (length(need) == 0) {
  log_step("All dependencies already installed: ", paste(targets, collapse = ", "))
  quit(save = "no", status = 0)
}
log_step("Missing: ", paste(need, collapse = ", "))

if (dry_run) {
  log_step("--dry-run: nothing installed")
  quit(save = "no", status = 0)
}

# ---------------------------------------------------------------------------
# 1. pak
# ---------------------------------------------------------------------------
use_pak <- requireNamespace("pak", quietly = TRUE)

if (!use_pak) {
  log_step("pak is not installed; trying to install it from CRAN")
  repos <- "https://cloud.r-project.org"
  ok <- tryCatch({
    utils::install.packages("pak", repos = repos)
    requireNamespace("pak", quietly = TRUE)
  }, error = function(e) {
    log_step("Installing pak failed: ", conditionMessage(e))
    FALSE
  })
  if (isTRUE(ok)) use_pak <- TRUE
}

if (use_pak) {
  log_step("Installing with pak::pak() (prefers precompiled binaries)")
  ok <- tryCatch({
    # pak resolves CRAN and Bioconductor together, so the packages do not have
    # to be split by repository.
    pak::pak(need)
    TRUE
  }, error = function(e) {
    log_step("pak failed: ", conditionMessage(e))
    log_step("Falling back to install.packages() / BiocManager::install()")
    FALSE
  })
  if (isTRUE(ok)) {
    still <- missing(targets)
    if (length(still) == 0) {
      log_step("All dependencies installed")
      quit(save = "no", status = 0)
    }
    log_step("Still missing after pak: ", paste(still, collapse = ", "))
    need <- still
  }
}

# ---------------------------------------------------------------------------
# 2. install.packages() + BiocManager::install()
# ---------------------------------------------------------------------------
repos <- c(CRAN = "https://cloud.r-project.org", BioCsoft = "https://bioconductor.org/packages/release/bioc")

bioc_pkgs <- c("Biostrings", "IRanges", "Rsamtools", "DECIPHER", "pwalign")
cran_pkgs <- setdiff(need, bioc_pkgs)

if (length(cran_pkgs) > 0) {
  log_step("install.packages(): ", paste(cran_pkgs, collapse = ", "))
  utils::install.packages(cran_pkgs, repos = repos[["CRAN"]])
}

if (length(intersect(need, bioc_pkgs)) > 0) {
  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    log_step("Installing BiocManager")
    utils::install.packages("BiocManager", repos = repos[["CRAN"]])
  }
  if (requireNamespace("BiocManager", quietly = TRUE)) {
    log_step("BiocManager::install(): ", paste(intersect(need, bioc_pkgs), collapse = ", "))
    BiocManager::install(intersect(need, bioc_pkgs), ask = FALSE, update = FALSE)
  } else {
    log_step("BiocManager unavailable; skipped Bioconductor packages")
  }
}

still <- missing(targets)
if (length(still) > 0) {
  log_step("STILL MISSING: ", paste(still, collapse = ", "))
  log_step("Install them manually, then re-run: sh 02_code/cli/nanoamp doctor")
  quit(save = "no", status = 1)
}
log_step("All dependencies installed")
log_step("Next: R CMD INSTALL 02_code")
