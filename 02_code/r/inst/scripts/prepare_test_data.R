#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# 整理 test_data，生成 ln_test_data 软链接与 manifest.tsv
# 只处理有 FASTQ 的三组数据：TSM20260826、ZNF8、nano_seq
# ---------------------------------------------------------------------------

suppressPackageStartupMessages(library(data.table))

script_path <- local({
  a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(a)) sub("^--file=", "", a[1]) else NA_character_
})

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

start_dir <- if (!is.na(script_path)) dirname(script_path) else getwd()
project_root <- find_project_root(start_dir)

test_dir <- file.path(project_root, "01_data", "test_data")
ln_dir <- file.path(project_root, "01_data", "ln_test_data")

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x)) y else x

rel_to_root <- function(path) {
  if (!grepl("^/", path)) path <- file.path(project_root, path)
  sub(paste0("^", project_root, "/?"), "", path)
}

rel_path <- function(from_dir, to_abs) {
  from <- strsplit(normalizePath(from_dir, mustWork = FALSE), "/", fixed = TRUE)[[1]]
  to <- strsplit(normalizePath(to_abs, mustWork = FALSE), "/", fixed = TRUE)[[1]]
  common <- 0L
  while (common < min(length(from), length(to)) &&
         from[common + 1L] == to[common + 1L]) {
    common <- common + 1L
  }
  up <- rep("..", length(from) - common)
  paste(c(up, to[(common + 1L):length(to)]), collapse = "/")
}

role_filename <- function(role, cluster = NULL) {
  switch(
    role,
    reads = "reads.fastq",
    reference.self = "reference.self.fa",
    reference.wt = "reference.wt.fa",
    consensus = sprintf("consensus.%d.fa", as.integer(cluster)),
    variants = sprintf("variants.%d.xlsx", as.integer(cluster)),
    sanger = sprintf("sanger.%d.ab1", as.integer(cluster)),
    stop(sprintf("未知 role: %s", role))
  )
}

manifest <- list()
add_link <- function(dataset, sample, role, cluster, target_abs, note = "") {
  if (is.na(target_abs) || !file.exists(target_abs)) {
    warning(sprintf("源文件不存在，跳过: %s", target_abs), call. = FALSE)
    return(invisible(FALSE))
  }
  sample_dir <- file.path(ln_dir, dataset, sample)
  dir.create(sample_dir, recursive = TRUE, showWarnings = FALSE)
  link_abs <- file.path(sample_dir, role_filename(role, cluster))
  if (file.exists(link_abs) || nzchar(Sys.readlink(link_abs))) unlink(link_abs)
  file.symlink(rel_path(dirname(link_abs), target_abs), link_abs)
  manifest[[length(manifest) + 1L]] <<- data.table::data.table(
    dataset = dataset,
    sample = sample,
    role = role,
    cluster = if (is.null(cluster)) NA_integer_ else as.integer(cluster),
    link_path = rel_to_root(link_abs),
    target_path = rel_to_root(target_abs),
    source_note = note
  )
  invisible(TRUE)
}

if (dir.exists(ln_dir)) {
  if (basename(ln_dir) != "ln_test_data") stop("安全检查失败：拒绝删除非 ln_test_data 目录")
  unlink(ln_dir, recursive = TRUE, force = TRUE)
}
dir.create(ln_dir, recursive = TRUE, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 通用：解析 TSM 风格的平铺目录（样本名_项目号_孔位.簇号.后缀）
# ---------------------------------------------------------------------------
parse_cluster <- function(base, pattern) {
  hit <- regmatches(base, regexec(pattern, base))[[1]]
  if (length(hit) < 2) return(NA_integer_)
  as.integer(hit[2])
}

build_flat_dataset <- function(dir_name, dataset, project_tag, wt_map) {
  d <- file.path(test_dir, dir_name)
  files <- list.files(d, full.names = TRUE)
  base <- basename(files)
  fq <- files[grepl("\\.fastq$", base)]
  samples <- unique(sub(paste0("_", project_tag, ".*$"), "", basename(fq)))
  samples <- sort(samples)

  consensus1 <- list()
  for (s in samples) {
    sfiles <- files[startsWith(base, paste0(s, "_", project_tag))]
    sbase <- basename(sfiles)
    reads <- sfiles[grepl("\\.fastq$", sbase)][1]
    cons <- sfiles[grepl("\\.([0-9]+)\\.seq$", sbase)]
    cons_cluster <- vapply(basename(cons), parse_cluster, integer(1),
                           pattern = "\\.([0-9]+)\\.seq$")
    cons <- cons[!is.na(cons_cluster)]
    cons_cluster <- cons_cluster[!is.na(cons_cluster)]
    for (i in seq_along(cons)) {
      add_link(dataset, s, "consensus", cons_cluster[i], cons[i])
      if (cons_cluster[i] == 1L) consensus1[[s]] <- cons[i]
    }
    vars <- sfiles[grepl("\\.([0-9]+)\\.变异统计表\\.xlsx$", sbase)]
    vc <- vapply(basename(vars), parse_cluster, integer(1),
                 pattern = "\\.([0-9]+)\\.变异统计表\\.xlsx$")
    for (i in seq_along(vars)) if (!is.na(vc[i])) add_link(dataset, s, "variants", vc[i], vars[i])
    ab1 <- sfiles[grepl("\\.([0-9]+)_1\\.ab1$", sbase)]
    ac <- vapply(basename(ab1), parse_cluster, integer(1),
                 pattern = "\\.([0-9]+)_1\\.ab1$")
    for (i in seq_along(ab1)) if (!is.na(ac[i])) add_link(dataset, s, "sanger", ac[i], ab1[i])
    add_link(dataset, s, "reads", NULL, reads)
  }

  for (s in samples) {
    self <- consensus1[[s]]
    if (is.null(self)) next
    add_link(dataset, s, "reference.self", NULL, self,
             note = "公司主导共识序列（cluster 1）")
    wt_name <- wt_map(s)
    if (!is.null(wt_name) && !is.null(consensus1[[wt_name]])) {
      wt <- consensus1[[wt_name]]
      if (normalizePath(wt, mustWork = FALSE) != normalizePath(self, mustWork = FALSE)) {
        add_link(dataset, s, "reference.wt", NULL, wt,
                 note = sprintf("独立对照参考: %s", wt_name))
      }
    }
  }
}

# ---------------------------------------------------------------------------
# TSM20260826
# ---------------------------------------------------------------------------
build_flat_dataset(
  dir_name = "TSM20260826-020-01254",
  dataset = "TSM20260826",
  project_tag = "TSM20260826-020-01254",
  wt_map = function(s) {
    if (s == "293T-E4" || startsWith(s, "E4-")) return("293T-E4")
    if (s == "293T-G2" || startsWith(s, "G2")) return("293T-G2")
    NULL
  }
)

# ---------------------------------------------------------------------------
# nano_seq
# ---------------------------------------------------------------------------
build_flat_dataset(
  dir_name = "nano_seq",
  dataset = "nano_seq",
  project_tag = "TSM20260917-020-01097",
  wt_map = function(s) {
    if (startsWith(s, "293T-G")) return(NULL)
    if (grepl("^G[0-9]+$", s)) return(paste0("293T-", s))
    NULL
  }
)

# ---------------------------------------------------------------------------
# ZNF8：克隆 + WT
# ---------------------------------------------------------------------------
znf8_dir <- file.path(test_dir, "ZNF8", "ZNF8")
wt_dir <- file.path(test_dir, "ZNF8", "2026.8.29-wt")
znf8_files <- list.files(znf8_dir, full.names = TRUE)
znf8_base <- basename(znf8_files)
clone_ids <- sort(unique(sub("_.*$", "", znf8_base[grepl("\\.fastq$", znf8_base)])),
                  decreasing = FALSE)
clone_ids <- clone_ids[grepl("^[0-9]+$", clone_ids)]
wt_cons <- list.files(wt_dir, pattern = "\\.1\\.seq$", full.names = TRUE)
wt_cons <- wt_cons[1]

for (id in clone_ids) {
  sample <- paste0("clone_", id)
  sfiles <- znf8_files[startsWith(znf8_base, paste0(id, "_TSM"))]
  sbase <- basename(sfiles)
  reads <- sfiles[grepl("\\.fastq$", sbase)][1]
  add_link("ZNF8", sample, "reads", NULL, reads)
  cons <- sfiles[grepl("\\.([0-9]+)\\.seq$", sbase)]
  cc <- vapply(basename(cons), parse_cluster, integer(1), pattern = "\\.([0-9]+)\\.seq$")
  for (i in seq_along(cons)) if (!is.na(cc[i])) add_link("ZNF8", sample, "consensus", cc[i], cons[i])
  vars <- sfiles[grepl("\\.([0-9]+)\\.变异统计表\\.xlsx$", sbase)]
  vc <- vapply(basename(vars), parse_cluster, integer(1),
               pattern = "\\.([0-9]+)\\.变异统计表\\.xlsx$")
  for (i in seq_along(vars)) if (!is.na(vc[i])) add_link("ZNF8", sample, "variants", vc[i], vars[i])
  ab1 <- sfiles[grepl("\\.([0-9]+)_1\\.ab1$", sbase)]
  ac <- vapply(basename(ab1), parse_cluster, integer(1), pattern = "\\.([0-9]+)_1\\.ab1$")
  for (i in seq_along(ab1)) if (!is.na(ac[i])) add_link("ZNF8", sample, "sanger", ac[i], ab1[i])
  self <- cons[cc == 1L][1]
  if (!is.na(self)) add_link("ZNF8", sample, "reference.self", NULL, self,
                             note = "公司主导共识序列（cluster 1）")
  add_link("ZNF8", sample, "reference.wt", NULL, wt_cons, note = "WT 对照")
}

# WT 样本自身
wt_files <- list.files(wt_dir, full.names = TRUE)
wt_base <- basename(wt_files)
wt_reads <- wt_files[grepl("\\.fastq$", wt_base)][1]
add_link("ZNF8", "WT", "reads", NULL, wt_reads)
add_link("ZNF8", "WT", "consensus", 1L, wt_cons[1])
add_link("ZNF8", "WT", "reference.self", NULL, wt_cons[1], note = "WT 自身共识")
wt_ab1 <- wt_files[grepl("\\.1_1\\.ab1$", wt_base)][1]
if (!is.na(wt_ab1)) add_link("ZNF8", "WT", "sanger", 1L, wt_ab1)

# ---------------------------------------------------------------------------
# 写出 manifest 与每样本 meta
# ---------------------------------------------------------------------------
manifest_dt <- data.table::rbindlist(manifest, use.names = TRUE)
data.table::setorder(manifest_dt, dataset, sample, role, cluster, na.last = TRUE)
data.table::fwrite(manifest_dt, file.path(ln_dir, "manifest.tsv"),
                   sep = "\t", na = "", quote = FALSE)

keys <- unique(manifest_dt[, .(dataset, sample)])
for (ki in seq_len(nrow(keys))) {
  key <- keys[ki]
  sub <- manifest_dt[dataset == key$dataset & sample == key$sample]
  data.table::fwrite(sub, file.path(ln_dir, key$dataset, key$sample, "meta.tsv"),
                     sep = "\t", na = "", quote = FALSE)
}

cat(sprintf("ln_test_data 已生成: %s\n", ln_dir))
cat(sprintf("软链接总数: %d\n", nrow(manifest_dt)))
print(manifest_dt[, .N, by = .(dataset, role)][order(dataset, role)])
