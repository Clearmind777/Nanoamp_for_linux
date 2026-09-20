# ---------------------------------------------------------------------------
# FASTA / FASTQ / 表格输入输出
# ---------------------------------------------------------------------------

read_fastq <- function(path) {
  if (!file.exists(path)) stop(sprintf("FASTQ 文件不存在: %s", path), call. = FALSE)
  fq <- if (grepl("\\.gz$", path, ignore.case = TRUE)) {
    con <- gzfile(path, "rt")
    on.exit(close(con), add = TRUE)
    ShortRead::readFastq(con)
  } else {
    ShortRead::readFastq(path)
  }
  if (length(fq) == 0) {
    return(data.table::data.table(
      read_id = character(0), sequence = character(0), quality = character(0)
    ))
  }
  qmat <- as(Biostrings::quality(fq), "matrix")
  qual_chr <- if (nrow(qmat) == 0) character(0) else {
    vapply(seq_len(nrow(qmat)), function(i) {
      q <- as.integer(qmat[i, ])
      q[is.na(q)] <- 0L
      q <- pmax(pmin(q, 93L), 0L)
      rawToChar(as.raw(q + 33L))
    }, character(1))
  }
  data.table::data.table(
    read_id = as.character(ShortRead::id(fq)),
    sequence = as.character(ShortRead::sread(fq)),
    quality = qual_chr
  )
}

count_fastq_reads <- function(path) {
  if (!file.exists(path)) stop(sprintf("FASTQ 文件不存在: %s", path), call. = FALSE)
  n <- ShortRead::countFastq(path)
  as.integer(n$records[1])
}

read_reference <- function(path) {
  if (!file.exists(path)) stop(sprintf("参考序列不存在: %s", path), call. = FALSE)
  x <- Biostrings::readDNAStringSet(path)
  if (length(x) == 0) stop(sprintf("参考序列为空: %s", path), call. = FALSE)
  seq <- toupper(as.character(x[[1]]))
  list(
    name = names(x)[1] %||% "reference",
    sequence = seq,
    length = nchar(seq),
    path = normalizePath(path, mustWork = TRUE),
    md5 = safe_md5(path)
  )
}

write_fasta <- function(sequences, path) {
  if (length(sequences) == 0) {
    file.create(path)
    return(invisible(path))
  }
  x <- Biostrings::DNAStringSet(toupper(sequences))
  names(x) <- names(sequences)
  Biostrings::writeXStringSet(x, path)
  invisible(path)
}

read_company_variants <- function(path) {
  if (is.null(path) || is.na(path) || !file.exists(path)) return(NULL)
  df <- tryCatch(
    readxl::read_excel(path, sheet = 1),
    error = function(e) {
      log_warn("无法读取公司变异表 ", path, ": ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(df) || nrow(df) == 0) return(NULL)
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  pick <- function(candidates) {
    hit <- intersect(candidates, colnames(df))
    if (length(hit) == 0) return(rep(NA, nrow(df)))
    df[[hit[1]]]
  }
  out <- data.table::data.table(
    company_pos = suppressWarnings(as.integer(pick(c("突变碱基位置", "Pos", "position")))),
    company_ref = as.character(pick(c("输出碱基", "Ref", "ref"))),
    company_alt = as.character(pick(c("变异碱基", "Alt", "alt"))),
    company_type = as.character(pick(c("变异类型", "type"))),
    company_freq = suppressWarnings(as.numeric(pick(c("变异比例(%)", "Freq", "freq"))))
  )
  out[]
}
