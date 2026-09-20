# ---------------------------------------------------------------------------
# minimap2 alignment and BAM parsing
# ---------------------------------------------------------------------------

align_reads <- function(reads_path, reference_path, out_bam,
                        threads = 4L, minimap2 = "minimap2", samtools = "samtools") {
  minimap2_bin <- check_external_tool(minimap2)
  samtools_bin <- check_external_tool(samtools)
  ensure_dir(dirname(out_bam))

  log_file <- paste0(out_bam, ".minimap2.log")
  cmd <- sprintf(
    "%s -ax map-ont --cs -t %d %s %s 2> %s | %s sort -@ %d -o %s -",
    shQuote(minimap2_bin), as.integer(threads),
    shQuote(normalizePath(reference_path, mustWork = TRUE)),
    shQuote(normalizePath(reads_path, mustWork = TRUE)),
    shQuote(log_file),
    shQuote(samtools_bin), as.integer(threads), shQuote(out_bam)
  )
  status <- system(cmd)
  if (status != 0 || !file.exists(out_bam)) {
    stop(sprintf("minimap2/samtools alignment failed with exit code %s", status),
         call. = FALSE)
  }
  system2(samtools_bin, c("index", shQuote(out_bam)), stdout = FALSE, stderr = FALSE)
  out_bam
}

parse_alignments <- function(bam, samtools = "samtools") {
  check_external_tool(samtools)
  flag <- Rsamtools::scanBamFlag(
    isUnmappedQuery = FALSE,
    isSecondaryAlignment = FALSE,
    isSupplementaryAlignment = FALSE
  )
  param <- Rsamtools::ScanBamParam(
    what = c("qname", "flag", "rname", "pos", "cigar", "seq", "mapq"),
    tag = c("cs", "NM"),
    flag = flag
  )
  b <- Rsamtools::scanBam(bam, param = param)[[1]]
  if (length(b$qname) == 0) {
    return(data.table::data.table(
      read_id = character(0), flag = integer(0), ref_name = character(0),
      ref_start = integer(0), cigar = character(0), read_seq = character(0),
      mapq = integer(0), cs = character(0), nm = integer(0)
    ))
  }
  cs <- b$tag$cs
  if (is.null(cs)) cs <- rep(NA_character_, length(b$qname))
  nm <- b$tag$NM
  if (is.null(nm)) nm <- rep(NA_integer_, length(b$qname))
  data.table::data.table(
    read_id = as.character(b$qname),
    flag = as.integer(b$flag),
    ref_name = as.character(b$rname),
    ref_start = as.integer(b$pos),
    cigar = as.character(b$cigar),
    read_seq = toupper(as.character(b$seq)),
    mapq = as.integer(b$mapq),
    cs = as.character(cs),
    nm = as.integer(nm)
  )
}

count_bam_reads <- function(bam, mapped_only = FALSE) {
  flag <- if (mapped_only) Rsamtools::scanBamFlag(isUnmappedQuery = FALSE) else Rsamtools::scanBamFlag()
  as.integer(Rsamtools::countBam(bam, param = Rsamtools::ScanBamParam(flag = flag))$records)
}

alignment_read_strand <- function(flag) {
  ifelse(bitwAnd(as.integer(flag), 16L) > 0L, "-", "+")
}

cs_tokenize <- function(cs) {
  if (is.null(cs) || length(cs) == 0 || is.na(cs) || !nzchar(cs)) return(character(0))
  cs <- sub("^cs:Z:", "", cs)
  regmatches(cs, gregexpr("(:[0-9]+|\\*[A-Za-z]{2}|\\+[A-Za-z]+|-[A-Za-z]+)", cs))[[1]]
}

cs_ref_span <- function(cs) {
  tokens <- cs_tokenize(cs)
  if (!length(tokens)) return(0L)
  parts <- vapply(tokens, function(tok) {
    c0 <- substr(tok, 1, 1)
    if (c0 == ":") as.integer(sub("^:", "", tok))
    else if (c0 == "*") 1L
    else if (c0 == "-") nchar(tok) - 1L
    else 0L
  }, integer(1))
  as.integer(sum(parts))
}

prepare_alignment_stats <- function(aln, ref_len) {
  if (nrow(aln) == 0) {
    aln[, `:=`(ref_span = integer(0), identity = numeric(0),
               ref_end = integer(0), ref_cov = numeric(0),
               strand = character(0))]
    return(aln[])
  }
  aln <- data.table::copy(aln)
  aln[, strand := alignment_read_strand(flag)]
  aln[, ref_span := vapply(cs, cs_ref_span, integer(1))]
  aln[, nm := ifelse(is.na(nm), 0L, nm)]
  aln[, identity := 1 - nm / pmax(ref_span, 1L)]
  aln[, ref_end := ref_start + pmax(ref_span, 1L) - 1L]
  aln[, ref_cov := pmin(ref_span / ref_len, 1)]
  aln[]
}

filter_alignment_reads <- function(aln, min_identity = 0.90, min_ref_coverage = 0.90) {
  aln[!is.na(identity) & identity >= min_identity & ref_cov >= min_ref_coverage]
}
