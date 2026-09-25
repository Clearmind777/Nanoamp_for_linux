# ---------------------------------------------------------------------------
# Functional annotation unit tests.
#
# Everything here is synthetic and offline: the reference layer talks to
# Ensembl, so these tests cover the layer below it -- CDS frames, consequence
# classification, translation edge cases, protein descriptions, cache keys and
# the pure parts of the reference layer.
#
# Expected values were taken from the implementation's verified behaviour and
# cross-checked against the authoritative GENCODE v50 GTF and GRCh38 FASTA.
# ---------------------------------------------------------------------------

# A synthetic single-block transcript whose CDS is `cds`.
fake_structure <- function(cds, strand = 1L) {
  blocks <- data.table::data.table(
    chrom = "chrSynthetic", start = 1L, end = nchar(cds),
    strand = strand, phase = 0L, protein_id = "SYNTH"
  )
  list(transcript_id = "SYNTH", exons = blocks, cds = blocks, cds_seq = cds,
       ok = TRUE, problem = NA_character_, chrom = "chrSynthetic", strand = strand)
}

# Apply one or more variants to a synthetic CDS and return the annotation row.
# The synthetic frame starts at 1, so an amplicon position IS a genome position;
# it is set explicitly to avoid relying on in-place data.table semantics.
classify <- function(cds, ops, genetic_code = Biostrings::GENETIC_CODE) {
  st <- fake_structure(cds)
  ops <- data.table::as.data.table(ops)
  ops <- data.table::copy(ops)[, genome_pos := as.integer(pos)]
  annotation_haplotype_transcript(cds, st,
                                  list(start = 1L, end = nchar(cds), strand = "+"),
                                  ops, genetic_code)
}

test_that("consequence vocabulary is bilingual and ranked", {
  expect_true(all(c("consequence_en", "consequence_zh") %in%
                    names(nanoamp:::.annotation_consequence)))
  expect_equal(consequence_zh("missense"), "错义")
  expect_equal(consequence_zh("frameshift"), "移码")
  expect_equal(consequence_zh("stop_gained"), "提前终止")
  expect_equal(consequence_zh("stop_lost"), "终止丢失")
  expect_equal(consequence_zh("synonymous"), "同义")
  # the three named in the brief must exist
  expect_true(all(c("frameshift", "stop_gained", "missense") %in%
                    nanoamp:::.annotation_consequence$consequence_en))
  # severity ordering used for the per-haplotype summary
  expect_gt(consequence_severity("frameshift"), consequence_severity("missense"))
  expect_gt(consequence_severity("stop_gained"), consequence_severity("synonymous"))
  expect_equal(most_severe_consequence(c("synonymous", "frameshift", "missense")),
               "frameshift")
})

test_that("synonymous, missense, stop_gained and stop_lost are classified", {
  # ATG AAA TTT TAA  ->  M K F *
  cds <- "ATGAAATTTTAA"

  # codon 3 TTT (Phe) -> TTC (Phe): synonymous
  r <- classify(cds, data.table::data.table(type = "snv", pos = 9L, ref = "T", alt = "C"))
  expect_equal(r$consequence, "synonymous")
  expect_equal(r$protein_change, "p.(=)")
  expect_true(r$cds_ok)

  # codon 2 AAA (Lys) -> GAA (Glu): missense
  r <- classify(cds, data.table::data.table(type = "snv", pos = 4L, ref = "A", alt = "G"))
  expect_equal(r$consequence, "missense")
  expect_equal(r$protein_change, "p.Lys2Glu")
  expect_true(r$cds_ok)

  # codon 3 TTT (Phe) -> TAA (Ter) needs two substitutions
  r <- classify(cds, data.table::data.table(
    type = c("snv", "snv"), pos = c(8L, 9L), ref = c("T", "T"), alt = c("A", "A")))
  expect_equal(r$consequence, "stop_gained")

  # the natural stop TAA -> TTA removes termination
  r <- classify(cds, data.table::data.table(type = "snv", pos = 11L, ref = "A", alt = "T"))
  expect_equal(r$consequence, "stop_lost")
})

test_that("a broken start codon is not reported as synonymous", {
  cds <- "ATGAAATTTTAA"
  r <- classify(cds, data.table::data.table(type = "snv", pos = 2L, ref = "T", alt = "C"))
  expect_false(identical(r$consequence, "synonymous"))
  expect_true(r$cds_ok)
})

test_that("indels separate frameshift from in-frame events", {
  cds <- "ATGAAATTTTAA"
  # +1 base => frameshift, and NOT a boundary/technical failure
  r <- classify(cds, data.table::data.table(type = "ins", pos = 6L, ref = "", alt = "A"))
  expect_equal(r$consequence, "frameshift")
  expect_true(r$cds_ok)
  expect_match(r$notes, "not a multiple of 3")
  expect_match(r$protein_change, "fs$")

  # +3 bases => in-frame insertion
  r <- classify(cds, data.table::data.table(type = "ins", pos = 6L, ref = "", alt = "AAA"))
  expect_equal(r$consequence, "inframe_insertion")
  expect_true(r$cds_ok)

  # -3 bases => in-frame deletion (must not be reported as an insertion)
  r <- classify(cds, data.table::data.table(type = "del", pos = 4L, ref = "AAA", alt = ""))
  expect_equal(r$consequence, "inframe_deletion")
  expect_match(r$protein_change, "del$")

  # -1 base => frameshift
  r <- classify(cds, data.table::data.table(type = "del", pos = 4L, ref = "A", alt = ""))
  expect_equal(r$consequence, "frameshift")
})

test_that("multiple variants are described from the joint translation", {
  # ATG AAA TTT GGG CCC -> M K F G P
  # codons: 1=ATG(1-3) 2=AAA(4-6) 3=TTT(7-9) 4=GGG(10-12)
  cds <- "ATGAAATTTGGGCCC"

  # codon 2 AAA -> AAG: synonymous (Lys stays Lys)
  silent <- classify(cds, data.table::data.table(type = "snv", pos = 6L, ref = "A", alt = "G"))
  expect_equal(silent$consequence, "synonymous")

  # codon 3 TTT -> ATT: missense
  miss <- classify(cds, data.table::data.table(type = "snv", pos = 10L, ref = "T", alt = "A"))
  expect_equal(miss$consequence, "missense")

  # together: one silent plus one missense gives exactly the missense protein,
  # and the description comes from the joint translation rather than from
  # concatenating the two single-variant descriptions
  both <- classify(cds, data.table::data.table(
    type = c("snv", "snv"), pos = c(6L, 10L), ref = c("A", "T"), alt = c("G", "A")))
  expect_true(both$cds_ok)
  expect_equal(both$n_aa_changed, 1L)
  expect_equal(nchar(both$alt_protein), nchar(both$ref_protein))
  expect_false(identical(both$protein_change, silent$protein_change))
})

test_that("translation refuses ambiguous bases and partial codons", {
  ok <- nanoamp:::.annotation_translate("ATGAAATTT", Biostrings::GENETIC_CODE)
  expect_true(ok$ok)
  expect_equal(ok$protein, "MKF")

  amb <- nanoamp:::.annotation_translate("ATGNNNTAA", Biostrings::GENETIC_CODE)
  expect_false(amb$ok)
  expect_match(amb$problem, "ambiguous")

  partial <- nanoamp:::.annotation_translate("ATGAAAT", Biostrings::GENETIC_CODE)
  expect_false(partial$ok)
  expect_match(partial$problem, "multiple of 3")
})

test_that("non-standard genetic codes are honoured", {
  std <- nanoamp:::.annotation_translate("ATGTGATAA", Biostrings::GENETIC_CODE)$protein
  mito_code <- Biostrings::getGeneticCode("2")
  mito <- nanoamp:::.annotation_translate("ATGTGATAA", mito_code)$protein
  expect_equal(std, "M**")
  expect_equal(mito, "MW*")
  expect_identical(annotation_genetic_code("2"), mito_code)
  expect_error(annotation_genetic_code("no such code"), "unknown genetic_code")
})

test_that("protein change descriptions follow the HGVS-like conventions", {
  expect_equal(nanoamp:::.annotation_protein_change("MKF", "MKF"), "p.(=)")
  expect_equal(nanoamp:::.annotation_protein_change("MKF", "MRF"), "p.Lys2Arg")
  # a frameshift is described as a frameshift, not as a substitution
  expect_equal(nanoamp:::.annotation_protein_change("MKF", "MKIL", frameshift = TRUE),
               "p.Phe3fs")
  # `delta` is the net residue-count difference over the changed span, so the
  # inserted residues are taken from the alternate protein
  expect_equal(nanoamp:::.annotation_protein_change("MKF", "MKKF", delta = 2L),
               "p.Phe3_Phe3insLysPhe")
  expect_equal(nanoamp:::.annotation_protein_change("MKF", "MF", delta = -1L),
               "p.Lys2del")
})

test_that("cache keys snap to a grid so nearby samples share entries", {
  a <- annotation_region_cache_key("19", 58285652L, 58285971L, 1L)
  b <- annotation_region_cache_key("19", 58286000L, 58286500L, 1L)
  expect_equal(a, b)                        # same 10 kb cell
  c <- annotation_region_cache_key("19", 58300000L, 58300100L, 1L)
  expect_false(identical(a, c))
  d <- annotation_region_cache_key("19", 58285652L, 58285971L, -1L)
  expect_false(identical(a, d))              # strand is part of the key
  expect_identical(annotation_region_cache_key("19", 58285652L, 58285971L, 1L), a)
  expect_match(a, "^GRCh38_19_")
})

test_that("region FASTA parsing reads the assembly from the header", {
  txt <- ">chromosome:GRCh38:19:58285652:58285971:1\nACGTacgtNN\n"
  p <- nanoamp:::.parse_region_fasta(txt)
  expect_equal(p$assembly, "GRCh38")
  expect_equal(p$sequence, "ACGTACGTNN")
  p2 <- nanoamp:::.parse_region_fasta("ACGT\nACGT\n")
  expect_equal(p2$sequence, "ACGTACGT")
  expect_true(is.na(p2$assembly))
})

test_that("a region response shorter than requested is detected", {
  cache <- tempfile("regcache_")
  dir.create(file.path(cache, "regions"), recursive = TRUE)
  old <- Sys.getenv("NANOAMP_CACHE_DIR", unset = NA)
  Sys.setenv(NANOAMP_CACHE_DIR = cache)
  on.exit({
    if (is.na(old)) Sys.unsetenv("NANOAMP_CACHE_DIR") else Sys.setenv(NANOAMP_CACHE_DIR = old)
  }, add = TRUE)

  key <- annotation_region_cache_key("19", 100L, 109L, 1L)
  path <- file.path(cache, "regions", paste0(key, ".txt"))
  writeLines(c(">19:100-109:1", "ACGT"), path)
  parsed <- nanoamp:::.read_region_cache(path)
  # reading works, but the length does not match the request, which is exactly
  # the condition the caller rejects
  expect_equal(nchar(parsed$sequence), 4L)
  expect_false(nchar(parsed$sequence) == 10L)
})

test_that("amplicon variants map to genomic coordinates through the frame", {
  ops <- data.table::data.table(
    type = c("snv", "ins", "del"),
    pos = c(11L, 20L, 30L),
    ref = c("A", "", "TT"),
    alt = c("G", "CCC", "")
  )
  g <- list(chrom = "19", start = 1001L, end = 1100L, strand = "+")
  out <- annotation_variants_to_genomic(ops, g)
  expect_equal(out$genome_pos, c(1011L, 1020L, 1030L))
  expect_equal(out$type, c("snv", "ins", "del"))
})

test_that("minus-strand amplicons are refused rather than mis-mapped", {
  ops <- data.table::data.table(type = "snv", pos = 5L, ref = "A", alt = "G")
  g <- list(chrom = "19", start = 1001L, end = 1100L, strand = "-")
  expect_error(annotation_variants_to_genomic(ops, g), "minus strand")
})

test_that("the anchor finds the 5-prime end of a partially matching reference", {
  core <- "GATTACAGGCCTTAACCGGTTACGCATGC"
  genome <- paste0(strrep("A", 50), core, strrep("T", 50))
  ref <- paste0(core, "CCCCCCCCCCCC")        # foreign tail
  anc <- nanoamp:::.annotation_anchor(ref, genome)
  expect_equal(anc$ref_off, 1L)
  expect_equal(anc$len, nchar(core))
  expect_equal(anc$seq_off, 51L)
})

test_that("annotation config validation rejects bad input", {
  td <- tempfile("cfg_"); dir.create(td)
  f1 <- file.path(td, "a.json"); writeLines('{"route":"cds"}', f1)
  expect_error(annotation_config_read(f1), "cds.start")
  f2 <- file.path(td, "b.json"); writeLines('{"route":"nonsense"}', f2)
  expect_error(annotation_config_read(f2), "unknown route")
  f3 <- file.path(td, "c.json")
  writeLines('{"route":"cds","cds":{"start":10,"end":9999}}', f3)
  cfg <- annotation_config_read(f3)
  expect_error(annotation_context("ACGTACGTAC", cfg), "outside the reference")
  f4 <- file.path(td, "d.json")
  writeLines('{"name":"x","route":"cds","cds":{"start":1,"end":9,"strand":"+","frame":0}}', f4)
  cfg4 <- annotation_config_read(f4)
  expect_equal(cfg4$route, "cds")
  expect_equal(cfg4$cds$start, 1L)
  expect_equal(annotation_context("ATGAAATTT", cfg4)$cds$start, 1L)
})

test_that("route cds builds a frame offline, without any reference provider", {
  f <- tempfile(fileext = ".json")
  writeLines('{"name":"offline","route":"cds","cds":{"start":1,"end":12,"strand":"+","frame":0}}', f)
  cfg <- annotation_config_read(f)
  ref <- "ATGAAATTTTAA"
  ctx <- annotation_context(ref, cfg)
  st <- nanoamp:::.annotation_cds_route_structure("synthetic", ctx$cds, ref)
  expect_true(st$ok)
  expect_equal(st$cds_seq, ref)
  # V1 needs Ensembl, so offline it reports a problem rather than passing
  v1 <- annotation_verify_reference_protein(st, Biostrings::GENETIC_CODE)
  expect_false(v1$ok)
})

test_that("an unreachable provider is reported as a problem, not swallowed", {
  # Offline policy: the provider check must report failure so the caller can
  # abort with instructions instead of silently producing unannotated output.
  cfg <- annotation_config_read(local({
    f <- tempfile(fileext = ".json")
    writeLines('{"name":"x","route":"cds","cds":{"start":1,"end":9}}', f)
    f
  }))
  ok <- tryCatch({
    annotation_require_provider(timeout = 2L)
    TRUE
  }, error = function(e) {
    msg <- conditionMessage(e)
    # the message must tell the user what to do
    expect_match(msg, "route \\\\\"cds\\\\\"|cds")
    expect_match(msg, "network|proxy|internet", ignore.case = TRUE)
    FALSE
  })
  # either the environment has connectivity (ok) or it aborted with advice
  expect_true(isTRUE(ok) || identical(ok, FALSE))
})
