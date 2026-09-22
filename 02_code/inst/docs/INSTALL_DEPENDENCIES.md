# Installing dependencies for nanoamp

This guide explains how to install and configure `minimap2`, `samtools` and
the R packages required by `nanoamp` on Linux.

## 1. What is needed

| Dependency | Type | Required for |
|---|---|---|
| `minimap2` | external command | Modes A and B (read alignment) |
| `samtools` | optional external command | Compatibility fallback; Rsamtools is used by default |
| R packages | R packages | Core analysis |
| `DECIPHER` | optional R package | Mode B de novo clustering |

Mode C (raw exact matching) does not need `minimap2`. `samtools` is never
required because `Rsamtools::asBam()` handles SAM to BAM conversion.

## 1.1 Bundled tools and the R-native fallback

`nanoamp` looks for tools in this order:

1. `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS` environment variables;
2. `03_dependence/<os>-<arch>/bin/`;
3. `PATH`.

The repository bundles minimap2 2.31 for Linux x86_64 under
`03_dependence/linux-x86_64/bin/`. See `03_dependence/README.md` for the full
platform matrix. Windows dependency material is owned by the sister repository
`a_09_18_26_mapping_programs_dev_for_win`.

On platforms without a minimap2 binary (Linux ARM64, macOS), use the R-native
backend:

```r
run_haplotype_analysis(..., aligner = "r")
```

`samtools` is optional because `Rsamtools::asBam()` converts SAM to BAM by
default. Use `use_samtools = TRUE` only if you need the samtools path.

## 2. Linux

### Option A: conda / mamba (recommended)

```bash
conda create -n nanoamp -c conda-forge -c bioconda minimap2 samtools
conda activate nanoamp

which minimap2
minimap2 --version

which samtools
samtools --version
```

Then install R packages inside the same R environment (see section 3).

### Option B: system packages

Debian / Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y minimap2 samtools
```

CentOS / Rocky / AlmaLinux:

```bash
sudo dnf install -y minimap2 samtools
```

### Verify

```bash
which minimap2
which samtools

Rscript -e 'library(nanoamp); nanoamp_cli("doctor")'
```

## 2b. macOS (Intel and Apple Silicon)

The bundled binaries under `03_dependence/linux-x86_64/bin/` are Linux ELF files
and cannot run on macOS. Install `minimap2` from conda instead, which is the
same route as on Linux:

```bash
conda create -n nanoamp -c conda-forge -c bioconda \
  r-base minimap2 samtools \
  r-data.table r-optparse r-jsonlite r-readxl \
  bioconductor-biostrings bioconductor-rsamtools bioconductor-shortread \
  bioconductor-iranges bioconductor-decipher
conda activate nanoamp

R CMD INSTALL 02_code          # 02_code/ is the package root
sh 02_code/cli/nanoamp doctor  # platform: macos-arm64 (or macos-x86_64)
```

`doctor` then resolves `minimap2` from the conda environment through `PATH`, so
Modes A and B work normally. Without minimap2, Mode C still works and Modes A
and B can use the R-native backend (`aligner = "r"`).

Notes for Apple Silicon:

- install the **osx-arm64** conda build; a `osx-64` environment runs only under
  Rosetta and mixes architectures;
- `pwalign` is required for `pairwiseAlignment()` on Bioconductor >= 3.19; it is
  included in the command above and is also usable when Biostrings still exports
  a defunct stub (Biostrings >= 2.77.1).

## 3. R packages

Required:

```r
install.packages(c(
  "Biostrings", "Rsamtools", "ShortRead", "IRanges", "Matrix",
  "data.table", "optparse", "jsonlite", "readxl"
))
```

If the Bioconductor packages are not available from CRAN:

```r
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
BiocManager::install(c("Biostrings", "Rsamtools", "ShortRead", "IRanges"))
```

Optional:

```r
BiocManager::install("DECIPHER")          # Mode B clustering and consensus
BiocManager::install("pwalign")           # pairwiseAlignment() provider, required
                                          # by Mode B and by aligner = "r" on
                                          # Bioconductor >= 3.19
```

Install location used by this repository's local verification environment:

```bash
mamba create -y -p ./tmp/nanoamp-env -c conda-forge -c bioconda \
  r-base minimap2 samtools \
  r-data.table r-optparse r-jsonlite r-readxl \
  bioconductor-biostrings bioconductor-rsamtools bioconductor-shortread \
  bioconductor-iranges bioconductor-decipher \
  r-testthat r-pkgload
```

`tmp/` is ignored by Git, so the environment stays out of the repository.

## 4. Verification checklist

```r
library(nanoamp)
nanoamp_cli("doctor")
```

Expected output:

```text
nanoamp version: 0.1.0
R version: ...
Rscript: ...
  Biostrings   TRUE
  ...
  DECIPHER     TRUE
  minimap2     /path/to/minimap2
  samtools     /path/to/samtools
```

What to check:

- `minimap2` shows a path, not `NOT FOUND`;
- `samtools` is optional and may show `NOT FOUND` unless
  `use_samtools = TRUE`;
- R packages show `TRUE`;
- `DECIPHER` may be `FALSE`: Mode B still works with a fallback, but DECIPHER
  is recommended.

## 5. Dependency reduction status

The following improvements are already implemented:

1. `Rsamtools::asBam()` performs SAM to BAM conversion by default, so the
   `samtools` command is optional;
2. `aligner = "r"` provides an R-native pairwise alignment backend for small
   and medium datasets, and for Linux ARM64 / macOS platforms without minimap2;
3. `minimap2` remains the recommended backend for large datasets.

Set `use_samtools = TRUE` only if you explicitly need the samtools path.
