# nanoamp

[中文](README.md) | **English**

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

## Input data requirements

This section is a **contract**, not advice: prepare your data as described here and
the program will not fail on format or naming; deviate and the error message names
the requirement you broke. Every statement below matches what the code does.

### 1. The minimum you must provide

| # | Required | What | Notes |
|---|---|---|---|
| 1 | ✅ | **One FASTQ file** | All reads for the sample, unaligned and uncorrected (or QC-filtered) |
| 2 | ✅ | **One reference sequence (FASTA)** | The amplicon itself, **not a whole genome** |
| 3 | ✅ | **One output directory path** | Passed as `--outdir`; created if missing |

That is all. No GTF, no genome FASTA, no BAM, no variant table, no annotation
file — the transcript structure needed for functional annotation is fetched over
the network (see [Functional annotation](#functional-annotation)).

All three modes take the same inputs; only the algorithm differs:

| Mode | Reference needed? | Notes |
|---|---|---|
| **A** (reference-guided, default) | Yes | Recommended; gives exact variant coordinates on the amplicon |
| **B** (de novo clustering) | Still required as an argument | Used only for labels and coverage; clustering does not depend on it |
| **C** (exact matching) | Yes | Counts raw reads only; **functional annotation does not run** |

### 2. How to name the files

**The program does not parse file names.** It reads whatever content you pass to
`--reads` / `--reference`, so any legal file name works (non-ASCII included) and
no naming rule can make a run fail.

Naming only serves human and script traceability. It is still strongly recommended
to give the reads and the reference of one sample the **same prefix** and
distinguish them with a fixed suffix:

```text
<sample>_<batch>_<date>-<batch-no>-<barcode>-<well>.fastq   # reads
<sample>_<batch>_<date>-<batch-no>-<barcode>-<well>.1.seq   # reference (amplicon)
```

This is exactly how the test data in this repository is named:

```text
E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq   ← --reads
E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.1.seq   ← --reference
```

`01_data/manifest.tsv` is an **internal** table mapping short logical names
(dataset/sample/role) onto those real file names. It is a convenience for the test
scripts; **you do not need to provide one.**

### 3. FASTQ requirements

`.fastq` and `.fq` are accepted, as are the gzip-compressed `.fastq.gz` / `.fq.gz`.
Compression is decided by the **magic bytes (`1f 8b`)**: for a name that does not end
in `.gz` the program probes the magic itself, and for a `.gz` name R's `gzfile()`
decides the same way. Either way you never have to decompress by hand or rename the
file to `.gz`.

Required:

| Requirement | What happens otherwise |
|---|---|
| **Exactly 4 lines per record**: `@` header, sequence, `+` separator, quality | `Malformed FASTQ (N lines is not a multiple of 4)`, non-zero exit |
| Line 1 starts with `@` and line 3 with `+` | `Malformed FASTQ (expected a '@' header and a '+' separator ...)`, non-zero exit |
| One sequence line per record | Same as above — **line-wrapped sequences are not supported** |
| Non-empty file | `Mode A: no aligned reads`, non-zero exit |

About the quality string (line 4):

- It **must be present**, but its **content is never used**. The program does not
  filter on quality, does not weight by quality and reports no quality metric;
  alignment and deconvolution use the sequence only.
- It therefore **does not have to match the sequence length**; a placeholder such
  as `IIII...` runs fine.

About the sequence itself:

- Case-insensitive (upper-cased on read).
- `N` and other ambiguous bases are allowed; positions with `N` count as mismatches.
- No hard lower bound on read length, but fragments much shorter than the amplicon
  are more likely to be filtered out by alignment.

### 4. Reference sequence (FASTA) requirements

| Requirement | Notes / behaviour otherwise |
|---|---|
| Must be **FASTA** | `.seq`, `.fa`, `.fasta`, `.fas` all work — parsing is by content, **not by extension** (the test data's references are `.seq`). Content that is not FASTA makes Biostrings fail with a non-zero exit, e.g. `">" expected at beginning of line 1` |
| **Only the first record is used** | Extra records are **silently ignored**. Make sure the sequence you want is first |
| At least one non-empty sequence | Empty file: `Reference sequence is empty`, non-zero exit |
| Must be **the amplicon itself** | A whole genome aligns, but coordinates, functional annotation and product length become meaningless |
| Should be close to the real PCR product length | The reference length is written to `qc.tsv` as `reference_length` and drives coverage, so a mismatch shows up directly in `mean_coverage` |

The reference sets the **origin of every coordinate** in the outputs: positions in
`variants.tsv`, the alignment basis of `haplotypes.fasta`, and the CDS coordinates
used by functional annotation are all relative to the sequence you pass. **Changing
the reference invalidates the coordinates**, especially the JSON config of the `cds`
route.

### 5. Output directory and naming

The directory given to `--outdir` is created if it does not exist. Each run writes a
fixed set of files into it (`haplotypes.tsv`, `haplotypes.fasta`, `variants.tsv`,
`qc.tsv`, `run_manifest.json`, plus `annotation.tsv` when annotation is enabled).
**Re-running into the same directory overwrites it**, so use one directory per
sample:

```bash
--outdir 04_results/r/demo/E4-3
```

`run_manifest.json` records the `reference` (path, md5, length) and `reads_md5` of the
run, which is the direct way to check which two inputs a result came from.

### 6. Batch input: the sample sheet (optional)

For many samples, the `batch` subcommand takes a **tab-separated (TSV)** file:

```bash
sh 02_code/cli/nanoamp batch --sample-sheet samples.tsv --outdir 04_results/batch --mode A
```

```text
sample   reads                       reference                   ref_label
E4-3     data/E4-3_H08.fastq         data/E4-3_H08.1.seq          E4-3 self consensus
WT       data/WT_B11.fastq           data/WT_B11.1.seq            WT
clone_3  data/clone_3_F12.fastq      data/WT_B11.1.seq            WT (as reference)
```

| Column | Required | Meaning |
|---|---|---|
| `sample` | ✅ | Sample name; **also the output subdirectory**, so avoid `/` |
| `reads` | ✅ | FASTQ path (relative to the working directory, or absolute) |
| `reference` | ✅ | Reference sequence path |
| `ref_label` | no | Label written to the outputs; defaults to the file name |

The header must contain `sample`, `reads` and `reference`, otherwise the run fails and
lists the required columns. Each sample is written to `<outdir>/<sample>/`, plus a
summary.

### 7. Extra requirements for functional annotation (optional)

If you do not pass `--annotate-config`, none of this applies and the outputs are
byte-identical to a run without annotation.

You supply a JSON config, with **one of two routes**:

- `"route": "genome"` (default, **needs network**): the program locates the amplicon on
  GRCh38 and pulls Ensembl annotation itself; you provide no annotation files.
- `"route": "cds"` (**fully offline**): you give the CDS interval in the config.

`cds` coordinates are the easiest thing to get wrong:

| Requirement | Meaning |
|---|---|
| Coordinate system | Relative to **the sequence you passed to `--reference`**, **1-based, both ends inclusive** |
| Length | `end - start + 1` **must be a multiple of 3** |
| Strand | `"strand": "+"` or `"-"`; for `"-"` the coordinates are still written in the reference's forward numbering |
| Length not a multiple of 3 | Annotation is **skipped**; the run still exits 0 but `qc.tsv` carries `annotation_available = FALSE` and `annotation_skip_reason`, and `run_manifest.json` carries `annotation.available = false` plus `skipped_transcripts` |
| Some transcripts skipped out of several | `available` stays `true`, but `qc.tsv`'s `n_transcripts_skipped` and `annotation_skip_reason`, and `run_manifest.json`'s `skipped_transcripts`, record each one and why |

Ready-to-use examples: `02_code/configs/example_online.json` and
`02_code/configs/example_cds.json` (the latter already filled with the longest ORF of a
real amplicon). The full field reference is `02_code/configs/README.md`.

### 8. Common input errors and what they mean

| Message | Cause |
|---|---|
| `FASTQ file not found: ...` | The `--reads` path does not exist |
| `Reference sequence not found: ...` | The `--reference` path does not exist |
| `Malformed FASTQ (N lines is not a multiple of 4)` | A record is not 4 lines, or sequences are wrapped |
| `Malformed FASTQ (expected a '@' header ...)` | Line 1 is not `@`, line 3 is not `+`, or the file is not FASTQ |
| `Reference sequence is empty` | The reference file is empty |
| `Mode A: no aligned reads` | Empty FASTQ, or no read passed `--min-identity` / `--min-ref-coverage` |
| `sample-sheet must contain columns: ...` | The batch sheet is missing required columns |
| `Annotation config not found: ...` | Wrong `--annotate-config` path (note: abbreviations such as `--annotate` are not accepted) |
| `annotation_available = FALSE` in the output | Annotation was requested but produced nothing; the reason is in `annotation_skip_reason` on the same row |

All of these exit with a **non-zero status**; none of them produces a plausible-looking
half-finished result.

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

Whenever a transcript is skipped it is recorded - the console WARN cannot be
traced afterwards. `qc.tsv` gets `n_transcripts_annotated` /
`n_transcripts_skipped` and `annotation_skip_reason`; `run_manifest.json` gets
`annotation.skipped_transcripts` with the transcript and the reason. When every
transcript fails (for example a CDS whose length is not a multiple of 3) the
outputs additionally carry `annotation_available = FALSE` /
`annotation.available = false`. Both cases exit 0, because the sequence
analysis itself succeeded. **Check those fields to see which transcripts were
annotated; the rows in `annotation.tsv` alone do not tell you.**

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
The Ensembl release used is recorded in `run_manifest.json` as
`annotation.ensembl_release` — quote that value when reporting results.
**v0.1.0 does not implement `--ensembl-release`** (pinning a historical release
needs the Ensembl archive hosts); that is left for a later version.

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
release/         release artifacts and notes (large archives stay out of Git;
                 see release/README.md)
```

Releasing: `make release` builds everything under `release/` from the current tag,
`make release-check` only verifies, and `make release-publish` uploads to the
GitHub Release (needs `gh auth login` or `GH_TOKEN`). See `release/RELEASE_NOTES.md`.

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
`02_code/inst/docs/INSTALL_DEPENDENCIES.md`. `README.md` is the Chinese version of this file and is what the
repository shows by default.
