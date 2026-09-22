# ---------------------------------------------------------------------------
# RStudio 交互版：修改 CONFIG 后直接运行整个脚本
# 打开 02_code/nanoamp.Rproj；脚本会自动向上寻找项目根目录
#
# 输入路径对应 01_data/manifest.tsv 里的逻辑名（dataset=TSM20260826, sample=E4-3）：
#   role=reads           -> test_data/TSM20260826-020-01254/E4-3_..._H08.fastq
#   role=reference.self  -> test_data/TSM20260826-020-01254/E4-3_..._H08.1.seq
# 换样本时改下面的 project_tag / sample 前缀，或直接照抄 manifest.tsv 的 path。
# ---------------------------------------------------------------------------

find_project_root <- function(start = getwd()) {
  p <- normalizePath(start, mustWork = FALSE)
  repeat {
    if (dir.exists(file.path(p, "01_data")) || dir.exists(file.path(p, ".git"))) return(p)
    parent <- dirname(p)
    if (identical(parent, p)) break
    p <- parent
  }
  normalizePath(start, mustWork = FALSE)
}

project_root <- find_project_root()

sample_dir <- file.path(project_root, "01_data/test_data/TSM20260826-020-01254")
project_tag <- "TSM20260826-020-01254"
sample_prefix <- "E4-3"

CONFIG <- list(
  reads = file.path(sample_dir, sprintf("%s_%s_20260827-020-BAN05-5_H08.fastq", sample_prefix, project_tag)),
  reference = file.path(sample_dir, sprintf("%s_%s_20260827-020-BAN05-5_H08.1.seq", sample_prefix, project_tag)),
  mode = "A",
  outdir = file.path(project_root, "04_results/r/rstudio_demo/mode_A_self"),
  top_n = 20L,
  min_reads = 3L,
  min_freq = 0.02,
  min_identity = 0.90,
  identity_cutoff = 0.99,
  min_cluster_reads = 2L,
  consensus_method = "decipher",
  threads = 4L
)

if (!requireNamespace("nanoamp", quietly = TRUE)) {
  stop("The nanoamp R package is not installed. Run: R CMD INSTALL 02_code",
       call. = FALSE)
}
suppressPackageStartupMessages(library(nanoamp))

if (!file.exists(CONFIG$reads) || !file.exists(CONFIG$reference)) {
  stop(paste0(
    "找不到输入文件:\n  ", CONFIG$reads, "\n  ", CONFIG$reference,
    "\n请检查 01_data/manifest.tsv，或先运行 02_code/scripts/prepare_test_data.R"
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
