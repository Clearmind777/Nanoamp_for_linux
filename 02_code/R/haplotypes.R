# ---------------------------------------------------------------------------
# 统一调度入口
# ---------------------------------------------------------------------------

run_haplotype_analysis <- function(reads, reference, outdir,
                                   mode = c("A", "B", "C"),
                                   top_n = 20L,
                                   min_reads = 3L, min_freq = 0.02,
                                   min_identity = 0.90, min_ref_coverage = 0.90,
                                   homopolymer = 4L, strand_bias = 0.90,
                                   identity_cutoff = 0.99,
                                   min_cluster_reads = 2L,
                                   max_msa_seqs = 20L,
                                   consensus_method = "medoid",
                                   threads = 4L,
                                   keep_intermediates = TRUE,
                                   ref_label = NULL) {
  mode <- toupper(match.arg(mode, c("A", "B", "C")))
  switch(
    mode,
    A = run_mode_a(
      reads, reference, outdir, top_n = top_n,
      min_reads = min_reads, min_freq = min_freq,
      min_identity = min_identity, min_ref_coverage = min_ref_coverage,
      homopolymer = homopolymer, strand_bias = strand_bias,
      threads = threads, keep_intermediates = keep_intermediates,
      ref_label = ref_label
    ),
    B = run_mode_b(
      reads, reference, outdir, top_n = top_n,
      identity_cutoff = identity_cutoff, min_cluster_reads = min_cluster_reads,
      min_identity = min_identity, min_ref_coverage = min_ref_coverage,
      max_msa_seqs = max_msa_seqs, consensus_method = consensus_method,
      threads = threads, keep_intermediates = keep_intermediates,
      ref_label = ref_label
    ),
    C = run_mode_c(
      reads, reference, outdir, top_n = top_n,
      keep_intermediates = keep_intermediates, ref_label = ref_label
    )
  )
}
