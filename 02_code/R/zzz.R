# Silence R CMD check notes for data.table non-standard evaluation.
utils::globalVariables(c(
  ".", ".I", ".N", ".SD",
  "alt", "ci_high", "ci_low", "cluster", "cluster_id", "count",
  "dp", "dp_minus", "dp_plus", "end", "Filter_Reason", "Filter_Status",
  "freq", "hp_run", "iend", "istart", "key", "len", "minus", "n_snv",
  "n_ins", "n_del", "ov", "passed_filter", "plus", "pos", "proportion",
  "rank", "ref", "ref_fwd", "ref_rev", "region_key", "sample_read_id",
  "Seq", "signature", "start", "support", "type",
  "cs", "DP4", "flag", "haplotype_id", "is_reference", "nm", "read_id",
  "ref_cov", "ref_end", "ref_span", "ref_start", "strand", "variants"
))

# ---------------------------------------------------------------------------
# Pairwise alignment provider.
#
# Bioconductor 3.19 moved pairwiseAlignment(), pattern(), subject(), aligned()
# and score() out of Biostrings into the pwalign package.
#
# Three Biostrings generations have to be supported:
#   1. old (< 2.77): pairwiseAlignment() lives in Biostrings and works;
#   2. middle: the symbol is not exported any more ("not an exported object");
#   3. current (>= 2.77.1): the symbol is *still exported* but is defunct and
#      aborts at call time with
#        "pairwiseAlignment() has moved from Biostrings to the pwalign package"
#
# Because of generation 3 a test of the form
#   "pairwiseAlignment" %in% getNamespaceExports("Biostrings")
# is not sufficient, and it silently selected the defunct Biostrings version on
# Bioconductor >= 3.19. Prefer pwalign whenever it is installed; that is correct
# for generations 2 and 3, and harmless for generation 1.
# ---------------------------------------------------------------------------
.pa_env <- new.env(parent = emptyenv())
.pa_optional_package <- "pwalign"
.pa_fns <- c("pairwiseAlignment", "pattern", "subject", "aligned", "score")

.pa_exported <- function(ns, fn) {
  fn %in% getNamespaceExports(ns) && exists(fn, envir = ns, inherits = FALSE)
}

.pa_provider <- function() {
  if (requireNamespace(.pa_optional_package, quietly = TRUE)) {
    return(asNamespace(.pa_optional_package))
  }
  bs <- asNamespace("Biostrings")
  if (all(vapply(.pa_fns, .pa_exported, logical(1), ns = bs))) {
    return(bs)
  }
  stop(
    "Pairwise alignment is unavailable: this Biostrings build no longer ",
    "provides pairwiseAlignment() and the 'pwalign' package is not installed.\n",
    "Install it with: BiocManager::install(\"pwalign\")",
    call. = FALSE
  )
}

.onLoad <- function(libname, pkgname) {
  prov <- .pa_provider()
  for (fn in .pa_fns) {
    assign(fn, get(fn, envir = prov), envir = .pa_env)
  }
  assign("provider", environmentName(prov), envir = .pa_env)
  invisible()
}

pa_pairwise_alignment <- function(...) .pa_env$pairwiseAlignment(...)
pa_pattern <- function(x) .pa_env$pattern(x)
pa_subject <- function(x) .pa_env$subject(x)
pa_aligned <- function(x) .pa_env$aligned(x)
pa_score <- function(x) .pa_env$score(x)
pa_provider_name <- function() .pa_env$provider
