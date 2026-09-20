# ---------------------------------------------------------------------------
# cs tag 解析、候选变异发现与过滤
# ---------------------------------------------------------------------------

cs_to_variants <- function(cs, ref_start, strand = "+", read_id = NA_character_) {
  tokens <- cs_tokenize(cs)
  if (!length(tokens)) return(NULL)
  ref_cursor <- as.integer(ref_start)
  out <- vector("list", length(tokens))
  k <- 0L
  for (tok in tokens) {
    c0 <- substr(tok, 1, 1)
    if (c0 == ":") {
      ref_cursor <- ref_cursor + as.integer(sub("^:", "", tok))
    } else if (c0 == "*") {
      k <- k + 1L
      out[[k]] <- data.table::data.table(
        read_id = read_id, type = "snv", pos = ref_cursor,
        ref = toupper(substr(tok, 2, 2)), alt = toupper(substr(tok, 3, 3)),
        strand = strand
      )
      ref_cursor <- ref_cursor + 1L
    } else if (c0 == "+") {
      k <- k + 1L
      out[[k]] <- data.table::data.table(
        read_id = read_id, type = "ins", pos = max(ref_cursor - 1L, 0L),
        ref = "", alt = toupper(substring(tok, 2)), strand = strand
      )
    } else if (c0 == "-") {
      del_seq <- toupper(substring(tok, 2))
      k <- k + 1L
      out[[k]] <- data.table::data.table(
        read_id = read_id, type = "del", pos = ref_cursor,
        ref = del_seq, alt = "", strand = strand
      )
      ref_cursor <- ref_cursor + nchar(del_seq)
    }
  }
  if (k == 0L) return(NULL)
  data.table::rbindlist(out[seq_len(k)], use.names = TRUE)
}

variant_key <- function(type, pos, ref, alt) {
  paste(type, pos, ref, alt, sep = "|")
}

extract_read_variants <- function(aln) {
  if (nrow(aln) == 0) {
    return(data.table::data.table(
      read_id = character(0), type = character(0), pos = integer(0),
      ref = character(0), alt = character(0), strand = character(0)
    ))
  }
  chunks <- lapply(seq_len(nrow(aln)), function(i) {
    cs_to_variants(aln$cs[i], aln$ref_start[i], aln$strand[i], aln$read_id[i])
  })
  chunks <- chunks[!vapply(chunks, is.null, logical(1))]
  if (!length(chunks)) {
    return(data.table::data.table(
      read_id = character(0), type = character(0), pos = integer(0),
      ref = character(0), alt = character(0), strand = character(0)
    ))
  }
  vars <- data.table::rbindlist(chunks, use.names = TRUE)
  vars[, key := variant_key(type, pos, ref, alt)]
  vars[]
}

compute_coverage <- function(aln, ref_len) {
  cov <- integer(ref_len)
  if (nrow(aln) == 0) return(cov)
  ir <- IRanges::IRanges(
    start = pmax(aln$ref_start, 1L),
    end = pmin(aln$ref_end, ref_len)
  )
  ir <- ir[IRanges::width(ir) > 0]
  if (length(ir) == 0) return(cov)
  cv <- as.integer(IRanges::coverage(ir))
  out <- integer(ref_len)
  n <- min(length(cv), ref_len)
  if (n > 0) out[seq_len(n)] <- cv[seq_len(n)]
  out
}

discover_variants <- function(aln, ref_seq,
                              min_reads = 3L, min_freq = 0.02,
                              homopolymer = 4L, strand_bias = 0.90) {
  ref_len <- nchar(ref_seq)
  cov <- compute_coverage(aln, ref_len)
  cov_plus <- compute_coverage(aln[strand == "+"], ref_len)
  cov_minus <- compute_coverage(aln[strand == "-"], ref_len)

  vars <- extract_read_variants(aln)
  if (nrow(vars) == 0) {
    return(list(
      variants = data.table::data.table(),
      pass_keys = character(0),
      coverage = cov,
      qc_extra = list(n_variant_reads = 0L, n_raw_variants = 0L)
    ))
  }

  agg <- vars[, .(
    support = .N,
    plus = sum(strand == "+"),
    minus = sum(strand == "-"),
    sample_read_id = read_id[1]
  ), by = .(type, pos, ref, alt, key)]

  agg[, dp := cov[pmax(pmin(pos, ref_len), 1L)]]
  agg[, dp_plus := cov_plus[pmax(pmin(pos, ref_len), 1L)]]
  agg[, dp_minus := cov_minus[pmax(pmin(pos, ref_len), 1L)]]
  agg[, freq := support / pmax(dp, 1L)]
  agg[, hp_run := mapply(
    function(tp, p, r) variant_homopolymer_run(ref_seq, tp, p, r),
    type, pos, ref, SIMPLIFY = TRUE, USE.NAMES = FALSE
  )]
  agg[, ref_fwd := pmax(dp_plus - plus, 0L)]
  agg[, ref_rev := pmax(dp_minus - minus, 0L)]
  agg[, `:=`(Filter_Status = "PASS", Filter_Reason = "")]

  agg[support < min_reads, `:=`(
    Filter_Status = "FILTERED",
    Filter_Reason = sprintf("支持 reads 数 < %d", min_reads)
  )]
  agg[Filter_Status == "PASS" & freq < min_freq, `:=`(
    Filter_Status = "FILTERED",
    Filter_Reason = sprintf("频率 < %.1f%%", min_freq * 100)
  )]
  agg[Filter_Status == "PASS" & plus > 0 & minus > 0 &
        pmin(plus, minus) / support < (1 - strand_bias), `:=`(
    Filter_Status = "FILTERED",
    Filter_Reason = "链偏好"
  )]
  agg[Filter_Status == "PASS" & hp_run >= homopolymer & freq < 0.5, `:=`(
    Filter_Status = "FILTERED",
    Filter_Reason = sprintf("poly 结构长度 >= %d bp 且频率较低", homopolymer)
  )]

  agg[, Seq := mapply(
    function(p, r, a) seq_context(ref_seq, p, r, a),
    pos, ref, alt, SIMPLIFY = TRUE, USE.NAMES = FALSE
  )]
  agg[, DP4 := sprintf("DP4=%d,%d,%d,%d", ref_fwd, ref_rev, plus, minus)]
  data.table::setcolorder(agg, c(
    "type", "pos", "ref", "alt", "support", "plus", "minus",
    "dp", "freq", "DP4", "Seq", "hp_run",
    "Filter_Status", "Filter_Reason", "key"
  ))

  list(
    variants = agg[],
    pass_keys = agg[Filter_Status == "PASS", key],
    coverage = cov,
    qc_extra = list(
      n_variant_reads = data.table::uniqueN(vars$read_id),
      n_raw_variants = nrow(agg)
    )
  )
}

variants_to_company_table <- function(variants, ref_name = "reference") {
  if (nrow(variants) == 0) {
    return(data.table::data.table(
      Chr = character(0), Pos = integer(0), Ref = character(0), Alt = character(0),
      DP = integer(0), Ref_dp = integer(0), Alt_dp = integer(0), Freq = numeric(0),
      DP4 = character(0), Seq = character(0),
      Filter_Status = character(0), Filter_Reason = character(0)
    ))
  }
  out <- data.table::data.table(
    Chr = ref_name,
    Pos = variants$pos,
    Ref = ifelse(nzchar(variants$ref), variants$ref, "-"),
    Alt = ifelse(nzchar(variants$alt), variants$alt, "-"),
    DP = variants$dp,
    Ref_dp = variants$dp - variants$support,
    Alt_dp = variants$support,
    Freq = round(variants$freq, 5),
    DP4 = variants$DP4,
    Seq = variants$Seq,
    Filter_Status = variants$Filter_Status,
    Filter_Reason = variants$Filter_Reason
  )
  out[]
}
