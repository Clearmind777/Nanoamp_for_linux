# ---------------------------------------------------------------------------
# RStudio 交互版：修改 CONFIG 后直接运行整个脚本
# 工作目录：项目根目录（打开根目录的 nanoamp.Rproj）
# ---------------------------------------------------------------------------

CONFIG <- list(
  reads = "01_data/ln_test_data/TSM20260826/E4-3/reads.fastq",
  reference = "01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa",
  mode = "A",
  outdir = "04_results/rstudio_demo/mode_A_self",
  top_n = 20L,
  min_reads = 3L,
  min_freq = 0.02,
  min_identity = 0.90,
  identity_cutoff = 0.99,
  min_cluster_reads = 2L,
  consensus_method = "medoid",
  threads = 4L
)

code_dir <- "02_code"
source(file.path(code_dir, "R", "load_all.R"))

if (!file.exists(CONFIG$reads)) {
  stop(paste0(
    "找不到输入文件: ", CONFIG$reads,
    "\n请确认工作目录是项目根目录，或先运行 scripts/prepare_test_data.R"
  ), call. = FALSE)
}

res <- run_haplotype_analysis(
  reads = CONFIG$reads,
  reference = CONFIG$reference,
  outdir = CONFIG$outdir,
  mode = CONFIG$mode,
  top_n = CONFIG$top_n,
  min_reads = CONFIG$min_reads,
  min_freq = CONFIG$min_freq,
  min_identity = CONFIG$min_identity,
  identity_cutoff = CONFIG$identity_cutoff,
  min_cluster_reads = CONFIG$min_cluster_reads,
  consensus_method = CONFIG$consensus_method,
  threads = CONFIG$threads
)

cat("\n=== 运行完成 ===\n")
cat("输出目录:", normalizePath(CONFIG$outdir, mustWork = FALSE), "\n\n")
cat("QC:\n"); print(res$qc)
cat("\n单倍型（前 10 条）:\n")
print(utils::head(res$haplotypes, 10))
