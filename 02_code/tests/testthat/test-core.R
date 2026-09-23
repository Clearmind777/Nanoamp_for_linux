# Locate the repository root regardless of how the tests are run
# (testthat::test_dir / test_local / pkgload set different working
# directories): walk upwards until a directory containing 01_data is found.
project_root_test_root <- function() {
  start <- getwd()
  p <- normalizePath(start, mustWork = FALSE)
  repeat {
    if (dir.exists(file.path(p, "01_data"))) return(p)
    parent <- dirname(p)
    if (identical(parent, p)) break
    p <- parent
  }
  # Fall back to the documented layout: <repo>/02_code/tests/testthat
  normalizePath(file.path(start, "..", "..", ".."), mustWork = FALSE)
}

test_that("cs tag 可解析为 SNV / 插入 / 缺失", {
  v <- cs_to_variants(":5*ac:3+ag:2-tt", ref_start = 10)
  expect_equal(nrow(v), 3)
  expect_equal(v$type, c("snv", "ins", "del"))
  expect_equal(v$pos, c(15L, 18L, 21L))
  expect_equal(v$ref, c("A", "", "TT"))
  expect_equal(v$alt, c("C", "AG", ""))
})

test_that("apply_variants 正确应用 SNV / 插入 / 缺失", {
  ref <- "ACGTACGT"
  expect_equal(
    apply_variants(ref, data.table::data.table(type = "snv", pos = 3L, ref = "G", alt = "T")),
    "ACTTACGT"
  )
  expect_equal(
    apply_variants(ref, data.table::data.table(type = "ins", pos = 3L, ref = "", alt = "AA")),
    "ACGAATACGT"
  )
  expect_equal(
    apply_variants(ref, data.table::data.table(type = "del", pos = 3L, ref = "GT", alt = "")),
    "ACACGT"
  )
})

test_that("signature 与 ops 可往返", {
  sig <- "snv|3|G|T;del|5|AC|"
  ops <- signature_to_ops(sig)
  expect_equal(nrow(ops), 2)
  expect_equal(ops$type, c("snv", "del"))
})

test_that("方案 C 能识别正链和反链精确匹配", {
  td <- tempfile("nanoamp_c_"); dir.create(td)
  ref <- "ACGTAGCTTAAG"
  seqs <- c(ref, reverse_complement(ref), "ACGTACGTACGA", ref)
  fq <- file.path(td, "reads.fastq")
  ref_fa <- file.path(td, "ref.fa")
  write_test_fastq(seqs, fq)
  write_test_ref(ref, ref_fa)
  res <- run_mode_c(fq, ref_fa, file.path(td, "out"), top_n = 5)
  expect_equal(res$qc$n_exact_forward, 2)
  expect_equal(res$qc$n_exact_reverse, 1)
  expect_equal(res$qc$n_exact_either, 3)
})

test_that("方案 A 能在合成数据中恢复参考与突变单倍型", {
  skip_if_not(
    !is.null(nanoamp_tool_path("minimap2", required = FALSE)),
    "minimap2 not available"
  )
  td <- tempfile("nanoamp_a_"); dir.create(td)
  ref <- make_random_seq(300, seed = 11)
  mut <- ref
  substr(mut, 100, 100) <- ifelse(substr(mut, 100, 100) == "A", "T", "A")
  seqs <- c(rep(ref, 6), rep(mut, 4))
  fq <- file.path(td, "reads.fastq")
  ref_fa <- file.path(td, "ref.fa")
  write_test_fastq(seqs, fq)
  write_test_ref(ref, ref_fa)
  res <- run_mode_a(
    fq, ref_fa, file.path(td, "out"),
    top_n = 5, min_reads = 2, min_freq = 0.2, min_identity = 0.9
  )
  expect_equal(nrow(res$haplotypes), 2)
  expect_true(any(res$haplotypes$is_reference))
  expect_true(any(grepl("100", res$haplotypes$variants)))
  expect_equal(sum(res$haplotypes$count), 10)
  expect_equal(sum(res$haplotypes$proportion), 1, tolerance = 1e-8)
})

test_that("方案 B 能对合成数据产生簇并计数", {
  skip_if_not(
    !is.null(nanoamp_tool_path("minimap2", required = FALSE)),
    "minimap2 not available"
  )
  td <- tempfile("nanoamp_b_"); dir.create(td)
  ref <- make_random_seq(300, seed = 22)
  mut <- ref
  substr(mut, 120, 120) <- ifelse(substr(mut, 120, 120) == "A", "T", "A")
  seqs <- c(rep(ref, 8), rep(mut, 5))
  fq <- file.path(td, "reads.fastq")
  ref_fa <- file.path(td, "ref.fa")
  write_test_fastq(seqs, fq)
  write_test_ref(ref, ref_fa)
  res <- run_mode_b(
    fq, ref_fa, file.path(td, "out"),
    top_n = 5, identity_cutoff = 0.95, min_cluster_reads = 2,
    min_identity = 0.9, consensus_method = "decipher", max_msa_seqs = 20
  )
  expect_true(nrow(res$haplotypes) >= 1)
  expect_equal(sum(res$haplotypes$count), 13)
  expect_true(all(nchar(res$haplotypes$consensus) > 0))
  if (requireNamespace("DECIPHER", quietly = TRUE)) {
    expect_true(grepl("^DECIPHER", res$qc$clustering_method))
    expect_equal(res$qc$consensus_method, "decipher")
  }
})

test_that("test data manifest 的每个逻辑名都指向存在的真实文件", {
  data_root <- file.path(project_root_test_root(), "01_data")
  manifest_path <- file.path(data_root, "manifest.tsv")
  skip_if_not(file.exists(manifest_path), "01_data/manifest.tsv 尚未生成")
  m <- data.table::fread(manifest_path, sep = "\t", header = TRUE)
  expect_true(all(c("dataset", "sample", "role", "cluster", "path") %in% names(m)))
  expect_true(nrow(m) > 0)
  expect_false(any(is.na(m$path)))
  expect_false(any(!nzchar(m$path)))
  # manifest 不复制数据：path 一律是 test_data/ 下的真实文件
  expect_true(all(startsWith(m$path, "test_data/")))
  expect_true(all(file.exists(file.path(data_root, m$path))))
})

# ---------------------------------------------------------------------------
# FASTQ reader (base R since ShortRead was dropped)
# ---------------------------------------------------------------------------

test_that("FASTQ 解析器返回正确的列、id 与逐 read 质量长度", {
  td <- tempfile("nanoamp_fastq_"); dir.create(td)
  seqs <- c("ACGTACGT", "ACGT", "ACGTA")
  fq <- file.path(td, "reads.fastq")
  # qualities with visible length differences, all printable Phred+33
  lines <- as.vector(rbind(
    sprintf("@read%d extra description", seq_along(seqs)),
    seqs, "+",
    vapply(nchar(seqs), function(n) paste(rep("I", n), collapse = ""), character(1))
  ))
  writeLines(lines, fq)

  d <- read_fastq(fq)
  expect_equal(names(d), c("read_id", "sequence", "quality"))
  expect_equal(nrow(d), 3L)
  # the '@' is not part of the id, and the description after the first space is kept
  expect_equal(d$read_id[1], "read1 extra description")
  expect_equal(d$sequence, seqs)
  # quality must match the read it belongs to, not be padded to the longest read
  expect_equal(nchar(d$quality), nchar(d$sequence))
  expect_equal(count_fastq_reads(fq), 3L)
})

test_that("FASTQ 解析器能读 gzip，并拒绝畸形输入", {
  td <- tempfile("nanoamp_fastq_gz_"); dir.create(td)
  seqs <- c("ACGTACGT", "ACGT")
  plain <- file.path(td, "reads.fastq")
  write_test_fastq(seqs, plain)
  gz <- file.path(td, "reads.fastq.gz")
  con_in <- file(plain, "rt"); con_out <- gzfile(gz, "wt")
  writeLines(readLines(con_in), con_out); close(con_in); close(con_out)

  expect_equal(read_fastq(plain), read_fastq(gz))
  expect_equal(count_fastq_reads(gz), 2L)

  # a file whose line count is not a multiple of 4 must fail loudly
  broken <- file.path(td, "broken.fastq")
  writeLines(c("@r1", "ACGT", "+"), broken)
  expect_error(read_fastq(broken), "Malformed FASTQ")
  expect_error(count_fastq_reads(broken), "Malformed FASTQ")

  # a file that is not FASTQ at all must not be silently mis-parsed
  notfastq <- file.path(td, "not.fastq")
  writeLines(c("ACGT", "ACGT", "ACGT", "ACGT"), notfastq)
  expect_error(read_fastq(notfastq), "Malformed FASTQ")
})

test_that("空 FASTQ 返回空表而不是报错", {
  td <- tempfile("nanoamp_fastq_empty_"); dir.create(td)
  fq <- file.path(td, "empty.fastq"); file.create(fq)
  d <- read_fastq(fq)
  expect_equal(nrow(d), 0L)
  expect_equal(names(d), c("read_id", "sequence", "quality"))
  expect_equal(count_fastq_reads(fq), 0L)
})
