# nanoamp

`nanoamp` analyzes Oxford Nanopore reads from PCR amplicons. Given a FASTQ file
and a target sequence, it corrects sequencing errors, reconstructs haplotypes,
and reports the most abundant sequences with counts and proportions.

This repository is the command-line distribution of `nanoamp`. It ships the
`nanoamp` R package, the `nanoamp` CLI, and a **pre-bundled `minimap2` for all
four supported platforms** (Linux and macOS, x86_64 and arm64). A graphical
interface is not part of this repository.

It can also classify what each sequence difference means biologically
(**frameshift / premature stop / missense / synonymous**, plus UTR, intron and
splice-region effects). That needs transcript structure, which the program
fetches **online on demand** -- you do not prepare any GTF or genome FASTA.
See [Functional annotation](#functional-annotation).

## Installation

The alignment tool needs no installation: `03_dependence/<os>-<arch>/bin/minimap2`
is already in the repository and works on a fresh clone, offline, with no conda
or other package manager. Only the R packages have to be installed, so pick
whichever route suits your machine.

### Option A — conda (also installs R)

```bash
# 1. Create the environment (R and the R packages; minimap2 comes from the repo)
conda create -n nanoamp -c conda-forge -c bioconda \
  r-base \
  r-data.table r-optparse r-jsonlite r-readxl \
  bioconductor-biostrings bioconductor-rsamtools bioconductor-shortread \
  bioconductor-iranges bioconductor-decipher
conda activate nanoamp

# 2. Install the nanoamp package bundled in this repository
#    (02_code/ is the package root)
R CMD INSTALL 02_code

# 3. Verify the installation
sh 02_code/cli/nanoamp doctor
```

### Option B — use the R you already have

No conda needed. The helper script tries `pak::pak()` first, because pak resolves
CRAN and Bioconductor together and reuses the precompiled binaries that CRAN and
Bioconductor publish for macOS (arm64 and x86_64) and Windows; if pak is missing
it falls back to `install.packages()` plus `BiocManager::install()`.

```bash
# 1. Install the R dependencies (pak first, then install.packages/BiocManager)
Rscript 02_code/scripts/install_r_deps.R

# 2. Install the package and verify
R CMD INSTALL 02_code
sh 02_code/cli/nanoamp doctor
```

`doctor` prints the detected platform, the dependence directory, the R packages
it can see, and the resolved `minimap2` / `samtools` paths. With a bundled binary
in place, `minimap2` resolves inside the repository:

```text
platform: macos-arm64
dependence directory: /path/to/repo/03_dependence
  minimap2     /path/to/repo/03_dependence/macos-arm64/bin/minimap2 (2.31-r1302)
  samtools     NOT FOUND (optional; Rsamtools is used by default)
```

`samtools` is not bundled on purpose: `Rsamtools::asBam()` performs the
SAM -> BAM conversion. If a machine already has `samtools` on `PATH`,
`use_samtools = TRUE` will use it. Details, including how the bundled binaries
were verified to need nothing but OS libraries, are in `03_dependence/README.md`.

## Two different "alignments"

`minimap2` and `pwalign` are not two options for the same job:

- **read mapping** — `minimap2` aligns every read to the target and reports the
  variants it carries. This is the default (`aligner = "minimap2"`) and what
  Modes A and B use;
- **pairwise alignment** — Biostrings (or `pwalign` on Bioconductor >= 3.19)
  compares one sequence against one sequence. Only `aligner = "r"` — the
  R-native fallback for hosts the bundled binary does not fit — and the Mode B
  annotation of cluster consensus sequences use it.

The pairwise provider is resolved lazily, on first call, and FASTQ is read by the
base-R parser in `R/io.R` rather than by `ShortRead` (which imports `pwalign`
unconditionally). A Mode A or Mode C run with the bundled minimap2 therefore
loads and completes even when no pairwise provider is installed; `qc.tsv` records
which package supplied it, or `NA` when the backend was never used. Only
`aligner = "r"` and Mode B's cluster annotation need it, and they fail with an
explanatory message if it is missing. See `02_code/README.md` for details.

## Quick start

```bash
# List the files of one sample (logical name -> real file)
awk -F'\t' '$1=="TSM20260826" && $2=="E4-3"' 01_data/manifest.tsv

# Run one sample
sh 02_code/cli/nanoamp call \
  --reads 01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq \
  --reference 01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.1.seq \
  --mode A --top-n 20 \
  --outdir 04_results/r/demo/E4-3
```

See `02_code/README.md` for the analysis modes, all parameters, the output
schema and the R API; `02_code/ARCHITECTURE.md` for the directory layout.

## Functional annotation

`--annotate-config` turns on a functional annotation pass. It writes
`annotation.tsv` next to the usual outputs and adds consequence columns to
`qc.tsv`; without the flag nothing changes.

```bash
# What transcripts overlap this amplicon? (no annotation config needed)
sh 02_code/cli/nanoamp call \
  --reads sample.fastq --reference amplicon.fa --outdir out \
  --list-transcripts

# Annotate against the MANE Select transcript
sh 02_code/cli/nanoamp call \
  --reads sample.fastq --reference amplicon.fa --outdir out \
  --annotate-config 02_code/configs/example_online.json

# ...or against every overlapping transcript
sh 02_code/cli/nanoamp call ... --annotate-config cfg.json --transcript all

# with protein sequences, and per-variant detail
sh 02_code/cli/nanoamp call ... --annotate-config cfg.json \
  --annotation-proteins --annotation-detail
```

Annotation outputs:

| File | Content |
|---|---|
| `annotation.tsv` | one row per haplotype x selected transcript (bilingual consequence, protein change) |
| `variants_annotation.tsv` | only with `--annotation-detail`: one row per variant, with codons and amino acids |
| `qc.tsv` | extra annotation metrics (transcript count, consequence counts, conflicts) |
| `run_manifest.json` | an `annotation` block (source, Ensembl release, config, transcript checks) |

### Where the reference comes from

There is nothing to download by hand. The program locates the amplicon in
GRCh38 itself and takes transcript structure from the Ensembl REST API (the
GENCODE/Ensembl identifier system, so ids stay in the `ENST`/`ENSG` namespace).
Only the slices it needs are fetched -- a few kB per amplicon -- and they are
cached under the XDG cache directory:

```text
${XDG_CACHE_HOME:-~/.cache}/nanoamp/ref/
```

`--clear-cache` empties it, `--no-cache` re-fetches, `--cache-dir` relocates it.
The Ensembl release used is recorded in `run_manifest.json`, and
`--ensembl-release N` pins a specific one when a reproducible reference matters.

### Two routes, one pipeline

| Route | When | Needs |
|---|---|---|
| `genome` (default) | normal use: the program finds the amplicon and the transcript | internet |
| `cds` | the amplicon reference is not a plain GRCh38 fragment, or the machine is offline | nothing: give `cds.start` / `cds.end` on the amplicon |

Route `cds` is the offline fallback -- it only needs translation, so it works
air-gapped (`02_code/configs/example_cds.json`).

### Consequence vocabulary

Consequences are reported with an English enum and a Chinese label
(`consequence_en` / `consequence_zh`), so downstream code can filter on a stable
value while the table stays readable:

| English | 中文 |
|---|---|
| `frameshift` | 移码 |
| `stop_gained` | 提前终止 |
| `stop_lost` | 终止丢失 |
| `start_lost` | 起始丢失 |
| `inframe_insertion` / `inframe_deletion` | 整码插入 / 整码缺失 |
| `missense` | 错义 |
| `synonymous` | 同义 |
| `splice_region` | 剪接区 |
| `5_prime_UTR` / `3_prime_UTR` | 5'UTR / 3'UTR |
| `intron` | 内含子 |
| `outside_cds` | CDS 之外 |

Each haplotype also gets `consequence_any_transcript` (the most severe
consequence across the selected transcripts) and `transcript_conflict`, which
flags a haplotype whose consequence differs between transcripts -- the clearest
warning that the transcript choice matters.

### What is verified

Every run re-checks the frame before reporting anything:

1. **V1** -- the CDS we assemble is translated and compared against the protein
   Ensembl serves; a mismatch aborts the run instead of producing consequences
   built on a wrong reading frame.
2. **V2** -- CDS length, start codon, stop codon and block layout.
3. **V3** -- the amplicon's position is derived from an exact-match anchor and
   the coordinates are re-derived from it, so a partially matching reference
   cannot silently shift every coordinate.

If the providers are unreachable the run **fails with an error and a non-zero
exit code**; it never quietly returns results without the annotation you asked
for.

## Repository layout

```text
00_materials/    brief, development plan and work reports
01_data/         test data (test_data/ deliverables + manifest.tsv name mapping)
02_code/         R package source + CLI launchers + shared contracts + helper scripts
03_dependence/   pre-bundled minimap2 for 4 platforms + platform notes
04_results/      run outputs (ignored by Git except its README)
05_builds/       R CMD build / check artifacts
```

## Development platforms

The repository is developed on more than one machine; nothing in the code is
platform-specific, and since report 9 every supported platform has its own
bundled `minimap2`.

| Platform | Bundled binary | Status |
|---|---|---|
| Linux x86_64 | `linux-x86_64/bin/minimap2` (glibc >= 2.14) | original development platform, verified in reports 1-7 |
| Linux arm64 | `linux-arm64/bin/minimap2` (glibc >= 2.17) | bundled; needs a Linux arm64 host to execute |
| macOS x86_64 | `macos-x86_64/bin/minimap2` | bundled; also runs on Apple Silicon under Rosetta 2 |
| macOS arm64 | `macos-arm64/bin/minimap2` | current verification platform, report 8 |

On macOS arm64 a full local verification is:

```bash
make test             # testthat unit tests
make check            # R CMD build + R CMD check
make cli              # sh 02_code/cli/nanoamp doctor
make functional-test  # all datasets x modes A/B/C against 01_data/manifest.tsv
```

Last verified on macOS arm64 (R 4.5.3, Biostrings 2.78.0, pwalign 1.6.0,
DECIPHER 3.6.0, bundled `minimap2` 2.31 — no conda-provided tools on `PATH`):

| Check | Result |
|---|---|
| `R CMD INSTALL 02_code` | OK |
| `testthat` unit tests | all pass, none skipped |
| `R CMD check --no-manual` | **Status: OK** |
| `nanoamp doctor` | platform `macos-arm64`, all R packages `TRUE`, `minimap2` resolved from `03_dependence/macos-arm64/bin/` |
| `run_functional_tests.R` (3 datasets x 32 samples x modes A/B/C) | **168/168 runs OK** |

Cross-platform behaviour is unchanged where it was measured against the
Linux x86_64 baseline: Mode A reaches full position/allele agreement with the
company variant tables on **22/23** samples (same as `work_report.1.md`), and the
Mode C raw exact-match proportion has the same **12.0%** median.

Historical, Linux-x86_64-orientated documents were kept verbatim under
`00_materials/` (the work reports are a log and are not rewritten; reports 8 and 9
list the paths that changed), and the platform-specific dependency notes remain in
`02_code/inst/docs/INSTALL_DEPENDENCIES.md`. `README-CN.md` is the Chinese
version of this file.
