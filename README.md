# nanoamp

`nanoamp` analyzes Oxford Nanopore reads from PCR amplicons. Given a FASTQ file
and a target sequence, it corrects sequencing errors, reconstructs haplotypes,
and reports the most abundant sequences with counts and proportions.

This repository is the command-line distribution of `nanoamp`. It ships the
`nanoamp` R package, the `nanoamp` CLI, and — for Linux x86_64 — bundled
`minimap2` / `samtools` binaries. A graphical interface is not part of this
repository.

## Installation

All external dependencies are installed with conda. The same commands work on
Linux x86_64, Linux arm64 and macOS (Intel and Apple Silicon).

```bash
# 1. Create the environment (R, R packages, minimap2 and samtools)
conda create -n nanoamp -c conda-forge -c bioconda \
  r-base minimap2 samtools \
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

`doctor` prints the detected platform, the dependence directory, the R packages
it can see, and the resolved `minimap2` / `samtools` paths.

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

## Repository layout

```text
00_materials/    brief, development plan and work reports
01_data/         test data (test_data/ deliverables + manifest.tsv name mapping)
02_code/         R package source + CLI launchers + shared contracts + helper scripts
03_dependence/   bundled external tools (Linux x86_64) and platform notes
04_results/      run outputs (ignored by Git except its README)
05_builds/       R CMD build / check artifacts
```

## Development platforms

The repository is developed on more than one machine; nothing in the code is
platform-specific, but the bundled binaries and the verified environment are.

| Platform | Status | Notes |
|---|---|---|
| Linux x86_64 | original development platform | bundled `minimap2` 2.31 and `samtools` 1.12 under `03_dependence/linux-x86_64/bin/` are found automatically; verified in reports 1-7 |
| macOS arm64 (Apple Silicon) | current verification platform, report 8 | the bundled Linux binaries do not run here; install `minimap2` from conda (step 1 above), or use `--aligner r` |

On macOS arm64 a full local verification is:

```bash
conda activate nanoamp
make test             # testthat unit tests
make check            # R CMD build + R CMD check
make cli              # sh 02_code/cli/nanoamp doctor
make functional-test  # all datasets x modes A/B/C against 01_data/manifest.tsv
```

Last verified on macOS arm64 (R 4.5.3, Biostrings 2.78.0, pwalign 1.6.0,
DECIPHER 3.6.0, conda `minimap2` 2.31):

| Check | Result |
|---|---|
| `R CMD INSTALL 02_code` | OK |
| `testthat` unit tests | all pass, none skipped |
| `R CMD check --no-manual` | **Status: OK** |
| `nanoamp doctor` | platform `macos-arm64`, all R packages `TRUE`, minimap2/samtools resolved |
| `run_functional_tests.R` (3 datasets x 32 samples x modes A/B/C) | **168/168 runs OK** |

Cross-platform behaviour is unchanged where it was measured against the
Linux x86_64 baseline: Mode A reaches full position/allele agreement with the
company variant tables on **22/23** samples (same as `work_report.1.md`), and the
Mode C raw exact-match proportion has the same **12.0%** median.

Historical, Linux-x86_64-orientated documents were kept verbatim under
`00_materials/` (the work reports are a log and are not rewritten; report 8 lists
the paths that changed), and the Linux-specific dependency notes remain in
`02_code/inst/docs/INSTALL_DEPENDENCIES.md`. `README-CN.md` is the Chinese
version of this file.
