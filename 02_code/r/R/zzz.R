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
