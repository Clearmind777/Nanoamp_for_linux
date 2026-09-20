#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# nanoamp 命令行入口
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(optparse)
  library(data.table)
})

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[1]) else "scripts/nanoamp.R"
code_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
source(file.path(code_dir, "R", "load_all.R"))

usage <- function() {
  cat(
    "nanoamp - 纳米孔 PCR 产物单倍型分析\n\n",
    "用法:\n",
    "  Rscript nanoamp.R call   --reads <fastq> --reference <fasta> --outdir <dir> [--mode A|B|C]\n",
    "  Rscript nanoamp.R batch  --sample-sheet <tsv> --outdir <dir> [--mode A|B|C]\n",
    "  Rscript nanoamp.R doctor\n\n",
    "示例:\n",
    "  Rscript nanoamp.R call --reads sample.fastq --reference target.fa --mode A --top-n 20 --outdir out\n",
    "  Rscript nanoamp.R doctor\n",
    sep = ""
  )
}

call_options <- function() {
  list(
    make_option(c("--reads"), type = "character", help = "输入 FASTQ"),
    make_option(c("--reference"), type = "character", help = "目的序列 FASTA"),
    make_option(c("--outdir"), type = "character", help = "输出目录"),
    make_option(c("--mode"), type = "character", default = "A", help = "A/B/C，默认 A"),
    make_option(c("--top-n"), type = "integer", default = 20, help = "输出前 n 条单倍型"),
    make_option(c("--min-reads"), type = "integer", default = 3, help = "变异最低支持 reads 数"),
    make_option(c("--min-freq"), type = "double", default = 0.02, help = "变异最低频率"),
    make_option(c("--min-identity"), type = "double", default = 0.90, help = "read 最低 identity"),
    make_option(c("--identity-cutoff"), type = "double", default = 0.99, help = "方案 B 聚类 identity 阈值"),
    make_option(c("--min-cluster-reads"), type = "integer", default = 2, help = "方案 B 最小簇大小"),
    make_option(c("--consensus-method"), type = "character", default = "medoid",
                help = "方案 B 共识方法 medoid/decipher"),
    make_option(c("--threads"), type = "integer", default = 4, help = "线程数"),
    make_option(c("--ref-label"), type = "character", default = NULL, help = "参考标签"),
    make_option(c("--no-intermediates"), action = "store_true", default = FALSE,
                help = "不保留 BAM 等中间文件")
  )
}

cmd_call <- function(args) {
  opt <- optparse::parse_args(optparse::OptionParser(option_list = call_options()), args = args)
  if (is.null(opt$reads) || is.null(opt$reference) || is.null(opt$outdir)) {
    usage(); stop("call 需要 --reads、--reference、--outdir", call. = FALSE)
  }
  run_haplotype_analysis(
    reads = opt$reads, reference = opt$reference, outdir = opt$outdir,
    mode = opt$mode, top_n = opt$`top-n`,
    min_reads = opt$`min-reads`, min_freq = opt$`min-freq`,
    min_identity = opt$`min-identity`,
    identity_cutoff = opt$`identity-cutoff`,
    min_cluster_reads = opt$`min-cluster-reads`,
    consensus_method = opt$`consensus-method`,
    threads = opt$threads,
    keep_intermediates = !isTRUE(opt$`no-intermediates`),
    ref_label = opt$`ref-label`
  )
  invisible(TRUE)
}

cmd_batch <- function(args) {
  opt <- optparse::parse_args(optparse::OptionParser(option_list = list(
    make_option(c("--sample-sheet"), type = "character"),
    make_option(c("--outdir"), type = "character"),
    make_option(c("--mode"), type = "character", default = "A"),
    make_option(c("--top-n"), type = "integer", default = 20),
    make_option(c("--threads"), type = "integer", default = 4),
    make_option(c("--min-reads"), type = "integer", default = 3),
    make_option(c("--min-freq"), type = "double", default = 0.02),
    make_option(c("--min-identity"), type = "double", default = 0.90),
    make_option(c("--identity-cutoff"), type = "double", default = 0.99),
    make_option(c("--min-cluster-reads"), type = "integer", default = 2),
    make_option(c("--consensus-method"), type = "character", default = "medoid"),
    make_option(c("--no-intermediates"), action = "store_true", default = FALSE)
  )), args = args)
  if (is.null(opt$`sample-sheet`) || is.null(opt$outdir)) {
    usage(); stop("batch 需要 --sample-sheet 和 --outdir", call. = FALSE)
  }
  sheet <- data.table::fread(opt$`sample-sheet`, sep = "\t", header = TRUE)
  needed <- c("sample", "reads", "reference")
  if (!all(needed %in% names(sheet))) {
    stop(sprintf("sample-sheet 必须包含列: %s", paste(needed, collapse = ", ")), call. = FALSE)
  }
  summary_rows <- list()
  for (i in seq_len(nrow(sheet))) {
    outdir <- file.path(opt$outdir, sheet$sample[i])
    status <- "ok"; err <- ""
    res <- tryCatch({
      run_haplotype_analysis(
        reads = sheet$reads[i], reference = sheet$reference[i], outdir = outdir,
        mode = opt$mode, top_n = opt$`top-n`, threads = opt$threads,
        min_reads = opt$`min-reads`, min_freq = opt$`min-freq`,
        min_identity = opt$`min-identity`, identity_cutoff = opt$`identity-cutoff`,
        min_cluster_reads = opt$`min-cluster-reads`,
        consensus_method = opt$`consensus-method`,
        keep_intermediates = !isTRUE(opt$`no-intermediates`),
        ref_label = if ("ref_label" %in% names(sheet)) sheet$ref_label[i] else NULL
      )
      TRUE
    }, error = function(e) { status <<- "error"; err <<- conditionMessage(e); FALSE })
    summary_rows[[i]] <- data.table::data.table(
      sample = sheet$sample[i], mode = opt$mode, outdir = outdir,
      status = status, error = err
    )
  }
  out <- data.table::rbindlist(summary_rows, use.names = TRUE)
  dir.create(opt$outdir, recursive = TRUE, showWarnings = FALSE)
  data.table::fwrite(out, file.path(opt$outdir, "batch_summary.tsv"), sep = "\t", na = "")
  print(out)
  invisible(TRUE)
}

cmd_doctor <- function(args) {
  cat("nanoamp version:", nanoamp_version(), "\n")
  cat("R version:", R.version.string, "\n")
  cat("Rscript:", file.path(R.home("bin"), "Rscript"), "\n")
  pkgs <- c("Biostrings", "Rsamtools", "ShortRead", "data.table",
            "optparse", "jsonlite", "readxl", "DECIPHER")
  for (p in pkgs) cat(sprintf("  %-12s %s\n", p, requireNamespace(p, quietly = TRUE)))
  for (tool in c("minimap2", "samtools")) {
    path <- Sys.which(tool)
    cat(sprintf("  %-12s %s\n", tool, if (nzchar(path)) path else "NOT FOUND"))
  }
  invisible(TRUE)
}

args <- commandArgs(trailingOnly = TRUE)
cmd <- if (length(args) >= 1 && !grepl("^--", args[1])) args[1] else "help"
rest <- if (length(args) >= 1 && !grepl("^--", args[1])) args[-1] else args

if (cmd == "call") {
  cmd_call(rest)
} else if (cmd == "batch") {
  cmd_batch(rest)
} else if (cmd == "doctor") {
  cmd_doctor(rest)
} else {
  usage()
}
