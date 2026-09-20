# ---------------------------------------------------------------------------
# 默认参数集中说明文件
# 实际默认值定义在 R/utils.R::default_params()
# 如需修改，建议在本文件中定义覆盖列表，并在调用时显式传入。
# ---------------------------------------------------------------------------

nanoamp_config <- function() {
  list(
    top_n = 20L,
    min_reads = 3L,
    min_freq = 0.02,
    min_identity = 0.90,
    min_ref_coverage = 0.90,
    homopolymer = 4L,
    strand_bias = 0.90,
    identity_cutoff = 0.99,
    min_cluster_reads = 2L,
    max_msa_seqs = 20L,
    consensus_method = "medoid",
    threads = 4L,
    keep_intermediates = TRUE
  )
}
