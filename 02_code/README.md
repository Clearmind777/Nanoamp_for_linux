# nanoamp

`nanoamp` is an R package for analyzing Oxford Nanopore reads from PCR
amplicons. It aligns reads to a target sequence, corrects sequencing errors,
reconstructs haplotypes, and reports the most abundant sequences with counts
and proportions.

The package is designed for questions such as:

- How many reads match the intended PCR product exactly?
- What other sequences are present, and at what proportions?
- Which variants are real, and which are nanopore sequencing errors?
- Which haplotype carries which combination of variants?

## Installation

### 1. Install dependencies

```r
install.packages(c(
  "Biostrings", "Rsamtools", "IRanges", "Matrix",
  "data.table", "optparse", "jsonlite", "readxl"
))

# Recommended for Mode B (de novo clustering)
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
BiocManager::install("DECIPHER")

# Only needed by the R-native backend (aligner = "r") and by the Mode B
# consensus annotation, which use pairwise alignment. On Bioconductor >= 3.19
# pairwiseAlignment() moved from Biostrings to pwalign. The provider is
# resolved lazily, so Modes A and C with the bundled minimap2 never need it.
BiocManager::install("pwalign")
```

`ShortRead` is intentionally not in that list. It used to provide the FASTQ
reader, but it imports `pwalign` unconditionally, which forced a
pairwise-alignment provider onto every installation. nanoamp now reads FASTQ
with the small base-R parser in `R/io.R` instead.

### 2. Install `nanoamp`

From a built tarball (for example the one produced by `make check`; adjust the
version if needed):

```r
install.packages("05_builds/r/nanoamp_0.1.0.tar.gz", repos = NULL, type = "source")
```

From the source directory (`02_code/` is the package root, not a pure R package
repository, so the package files live at its top level):

```bash
R CMD INSTALL 02_code
```

During development:

```r
devtools::install("02_code")
```

### 3. Install external tools

`minimap2` is resolved from `03_dependence/<os>-<arch>/bin/` first, then from
`PATH`. `samtools` is optional: SAM to BAM conversion uses
`Rsamtools::asBam()` by default.

Detailed installation and `PATH` configuration instructions for Linux are in
[inst/docs/INSTALL_DEPENDENCIES.md](inst/docs/INSTALL_DEPENDENCIES.md).

`nanoamp` prefers tools from `03_dependence/<os>-<arch>/bin/`, then falls back
to `PATH`. The repository bundles minimap2 2.31 for Linux x86_64; the platform
support matrix and the R-native fallback are documented in
`03_dependence/README.md`.

```bash
minimap2 --version
# optional:
# samtools --version
```

Check everything from R:

```r
library(nanoamp)
nanoamp::nanoamp_cli("doctor")
```

## Quick start

```r
library(nanoamp)

res <- run_haplotype_analysis(
  reads     = "sample.fastq",
  reference = "target.fa",
  outdir    = "results/sampleA",
  mode      = "A",
  top_n     = 20
)

# Top haplotypes
res$haplotypes

# Candidate variants
res$variants

# QC metrics
res$qc
```

Basic input requirements:

- `reads`: FASTQ or FASTQ.GZ, single-end nanopore reads;
- `reference`: FASTA containing the intended amplicon sequence;
- `outdir`: output directory (created automatically).

## Analysis modes

### Mode A: reference-guided correction (recommended)

Mode A aligns reads to the target sequence, discovers candidate variants,
treats differences that do not pass the variant filters as sequencing errors,
and groups reads by their corrected sequence.

Use Mode A when:

- a reliable target sequence is available;
- you need quantitative haplotype proportions;
- you want to distinguish real variants from nanopore errors.

### Mode B: de novo clustering (exploratory)

Mode B clusters reads with `DECIPHER::Clusterize` and builds a polished
consensus for each cluster using `DECIPHER::AlignSeqs` followed by majority
voting.

Use Mode B when:

- no reliable reference is available;
- you want a data-driven overview of the main sequence groups;
- you accept that haplotypes differing by less than the sequencing error rate
  may not be resolved.

If `DECIPHER` is unavailable, Mode B falls back to variant-pattern greedy
clustering and records this in `qc.tsv`.

### Mode C: raw exact matching (diagnostic)

Mode C counts raw reads that match the reference exactly on either strand. It
is useful for demonstrating the effect of nanopore errors, but it is not
recommended for quantitative haplotype analysis.

## Functional annotation

Annotation answers what a sequence difference *means*: frameshift, premature
stop, missense, synonymous, plus UTR / intron / splice-region effects. It is
optional and driven by a JSON config; without `--annotate-config` nothing in the
output changes.

```r
library(nanoamp)
res <- run_haplotype_analysis(
  reads = "sample.fastq", reference = "amplicon.fa", outdir = "out",
  annotation = "02_code/configs/example_online.json"
)
res$annotation   # one row per haplotype x transcript
```

### Where the reference comes from

Nothing has to be downloaded by hand. The program locates the amplicon in GRCh38
itself and takes transcript structure from the Ensembl REST API, so identifiers
stay in the GENCODE/Ensembl namespace (`ENST`/`ENSG`). Only the slices it needs
are fetched -- a few kB per amplicon -- and they are cached under
`${XDG_CACHE_HOME:-~/.cache}/nanoamp/ref`. The Ensembl release is recorded in
`run_manifest.json`.

| Route | When | Needs |
|---|---|---|
| `genome` (default) | normal use | internet |
| `cds` | reference is not a plain GRCh38 fragment, or the host is offline | nothing: give `cds.start` / `cds.end` on the amplicon |

### Selecting transcripts

The consequence of a variant can differ between transcripts, so the transcript is
never chosen silently. The default is the MANE Select transcript, then Ensembl
canonical; if neither exists the run stops and prints the candidates. Select
explicitly with `transcript_id` in the config, or annotate all of them:

```r
# transcript_all / transcript_id live in the JSON config
run_haplotype_analysis(..., annotation = "configs/all_transcripts.json")

# from the CLI the same choice is a flag
#   nanoamp call ... --annotate-config cfg.json --transcript all
#   nanoamp call ... --annotate-config cfg.json --transcript ENST00000621650
```

Every haplotype row carries `consequence_any_transcript` (the most severe
consequence across the selected transcripts) and `transcript_conflict`, which is
set when a haplotype's consequence differs between transcripts.

### Consequence vocabulary

Consequences are reported in two columns, so downstream code can filter on a
stable value while the table stays readable:

`consequence_en` / `consequence_zh`: `frameshift` / 移码, `stop_gained` /
提前终止, `stop_lost` / 终止丢失, `start_lost` / 起始丢失, `inframe_insertion` /
整码插入, `inframe_deletion` / 整码缺失, `missense` / 错义, `synonymous` / 同义,
`splice_region` / 剪接区, `5_prime_UTR` / 5'UTR, `3_prime_UTR` / 3'UTR,
`intron` / 内含子, `outside_cds` / CDS 之外.

### Self-checks

Every annotation pass verifies its own frame before reporting anything:

1. **V1** -- the assembled CDS is translated and compared against the protein
   Ensembl serves; a mismatch aborts the run instead of emitting consequences
   built on a wrong reading frame.
2. **V2** -- CDS length, start codon, stop codon and block layout.
3. **V3** -- the amplicon position is derived from an exact-match anchor and the
   coordinates are re-derived from it.

Annotation is the only networked part of the package. When the providers are
unreachable it **fails with an error**; it never silently returns results without
the annotation that was requested. Route `cds` works air-gapped.

## Parameters

Default parameters can be inspected with:

```r
nanoamp_defaults()
```

| Parameter | Default | Description |
|---|---:|---|
| `top_n` | 20 | Number of top haplotypes to report |
| `min_reads` | 3 | Minimum supporting reads for a candidate variant |
| `min_freq` | 0.02 | Minimum variant frequency |
| `min_identity` | 0.90 | Minimum read identity to the reference |
| `min_ref_coverage` | 0.90 | Minimum fraction of the reference covered by a read |
| `homopolymer` | 4 | Homopolymer length threshold for filtering |
| `strand_bias` | 0.90 | Strand bias threshold |
| `identity_cutoff` | 0.99 | Mode B clustering identity cutoff |
| `min_cluster_reads` | 2 | Mode B minimum cluster size |
| `max_msa_seqs` | 100 | Maximum sequences per consensus alignment |
| `consensus_method` | `"decipher"` | `"decipher"` or `"medoid"` |
| `aligner` | `"minimap2"` | `"minimap2"` or `"r"` (R-native fallback) |
| `use_samtools` | `FALSE` | Use samtools instead of Rsamtools for SAM to BAM |
| `threads` | 4 | Number of threads |
| `keep_intermediates` | `TRUE` | Keep BAM and other intermediate files |
| `annotation` | `NULL` | Path to a functional annotation config (JSON); `NULL` disables annotation |
| `list_transcripts` | `FALSE` | Only print the candidate transcripts for the amplicon |
| `annotation_proteins` | `FALSE` | Include reference/alternate protein sequences in `annotation.tsv` |
| `annotation_detail` | `FALSE` | Also write `variants_annotation.tsv` with per-variant consequences |

## Output files

```text
outdir/
|-- haplotypes.tsv
|-- haplotypes.fasta
|-- variants.tsv
|-- qc.tsv
|-- run_manifest.json
`-- alignments.bam(.bai)     # Modes A and B, when keep_intermediates = TRUE
`-- annotation.tsv           # only when annotation is enabled
`-- variants_annotation.tsv  # only with annotation_detail = TRUE
```

### haplotypes.tsv

| Column | Description |
|---|---|
| `rank` | Rank by supporting read count |
| `haplotype_id` / `cluster_id` | Haplotype or cluster identifier |
| `count` | Supporting reads |
| `proportion` | Fraction of assigned reads |
| `ci_low`, `ci_high` | 95% Wilson confidence interval |
| `is_reference` | Whether the sequence matches the reference |
| `n_snv`, `n_ins`, `n_del` | Number of variants |
| `length` | Haplotype length |
| `variants` | Variant description; `.` means no variant |

### variants.tsv

Mode A uses a company-compatible layout:

```text
Chr  Pos  Ref  Alt  DP  Ref_dp  Alt_dp  Freq  DP4  Seq  Filter_Status  Filter_Reason
```

- `Freq` is a fraction between 0 and 1;
- `-` in `Ref` or `Alt` represents an insertion or deletion;
- `Filter_Status` is `PASS` or `FILTERED`.

### qc.tsv

Two columns, `metric` and `value`, including read counts, mapping rate, mean
identity, coverage, clustering method, consensus method, and DECIPHER version.

## Command line interface

The package ships a CLI based on the same R code.

```bash
nanoamp doctor

nanoamp call \
  --reads sample.fastq \
  --reference target.fa \
  --mode A \
  --top-n 20 \
  --outdir results/sampleA

nanoamp batch \
  --sample-sheet samples.tsv \
  --mode A \
  --outdir results/batch
```

The batch sample sheet is a TSV with at least:

```text
sample	reads	reference
```

Optional columns: `ref_label`.

Use `--aligner r` to select the R-native alignment backend on platforms
without minimap2. The repository-level launcher is `02_code/cli/nanoamp`.

### Install the `nanoamp` command

```bash
sh "$(Rscript --vanilla -e 'cat(system.file("scripts", "install_cli.sh", package = "nanoamp"))')" ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
nanoamp doctor
```

Alternatively, call the CLI directly from R:

```r
library(nanoamp)
nanoamp_cli(c("call", "--reads", "sample.fastq", "--reference", "target.fa",
              "--outdir", "results/sampleA"))
```

## External tools and the R-native backend

`aligner = "minimap2"` uses the bundled minimap2 binary when available.
On ARM platforms, macOS, or any machine without minimap2, use:

```r
run_haplotype_analysis(..., aligner = "r")
```

The R-native backend uses Biostrings pairwise alignment and requires no
external tool. It is slower and is intended for small and medium amplicons.

That pairwise alignment provider is resolved lazily, on first call, and the
result is cached:

- `aligner = "minimap2"` (the default) never touches it, so the package loads
  and runs a full analysis even when no pairwise provider is installed — this is
  exactly why the `ShortRead` FASTQ reader was replaced with the parser in
  `R/io.R`, since `ShortRead` would otherwise pull `pwalign` in unconditionally;
- `aligner = "r"`, and the Mode B annotation of cluster consensus sequences,
  resolve it on first use;
- `pwalign` is preferred when installed, otherwise Biostrings is used; only if
  neither provides `pairwiseAlignment()` does the call itself fail. `qc.tsv`
  records which provider supplied it (`NA` when the backend was never used).

`samtools` is optional: SAM -> BAM conversion uses `Rsamtools::asBam()` by
default. Set `use_samtools = TRUE` only if you explicitly want the samtools
path.

## RStudio workflow

1. Open `02_code/nanoamp.Rproj`.
2. Edit the `CONFIG` block in `02_code/scripts/run_analysis.R`.
3. Run the whole script.

The script locates the repository root automatically and writes results under
`04_results/r/`.

## Using the test data

The company file names are long, so `01_data/manifest.tsv` maps short logical
names (`dataset` / `sample` / `role`) onto the real files in `01_data/test_data/`.
The manifest stores no data and needs no preparation step; regenerate it from the
original deliverables with:

```bash
Rscript 02_code/scripts/prepare_test_data.R
# or: make test-data
```

Look up a sample:

```r
m <- data.table::fread("01_data/manifest.tsv")
m[dataset == "TSM20260826" & sample == "E4-3", .(role, cluster, path)]
```

Example:

```r
library(nanoamp)
res <- run_haplotype_analysis(
  reads     = "01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq",
  reference = "01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.1.seq",
  outdir    = "04_results/r/demo/E4-3",
  mode      = "A"
)
```

## Tests and verification

```r
# Unit tests
testthat::test_check("nanoamp")   # from an installed package

# Or during development
devtools::test("02_code")
```

Full functional test across datasets (inputs are resolved through
`01_data/manifest.tsv`):

```bash
Rscript 02_code/scripts/run_functional_tests.R \
  --outdir 04_results/r/test_run_local --modes A,B,C --threads 4
# or: make functional-test
```

The package has been verified with `R CMD check` and currently passes with
`Status: OK`.

## Troubleshooting

| Symptom | Solution |
|---|---|
| `minimap2` not found | Install minimap2 and add it to `PATH` |
| `samtools` not found | Usually not needed: `Rsamtools` is the default. Install samtools only if `use_samtools = TRUE` |
| Mode B is slow | Reduce `max_msa_seqs`, increase `threads`, or use `mode = "A"` |
| Mode B cannot separate close haplotypes | This is expected below the sequencing error rate; use Mode A |
| `DECIPHER` not installed | Mode B falls back to greedy clustering; install DECIPHER for better results |
| `pairwiseAlignment` is not an exported object from Biostrings | Only `aligner = "r"` and the Mode B annotation need pairwise alignment. Bioconductor >= 3.19 moved it to `pwalign`; install it with `BiocManager::install("pwalign")`. The default minimap2 workflow is unaffected |
| All proportions are low in Mode C | Nanopore reads contain errors; use Mode A |
| `Cannot annotate: the reference providers are not reachable` | Annotation needs Ensembl. Check network/proxy, retry with `--no-cache`, or use a `cds` config, which needs no network |
| `the amplicon reference matches ... only over N% of its length` | The reference is not a plain GRCh38 fragment (plasmid, chimeric or heavily edited). Use a `cds` config with explicit `cds.start` / `cds.end` |
| `no transcript selected and this locus has no MANE_Select` | Set `transcript_id` in the config, or `transcript_all = TRUE` |
| Annotation is slow | Each transcript costs a few requests and they are throttled; annotate a single transcript, and reruns hit the cache |

## License

MIT.
