# Installing dependencies for nanoamp

nanoamp needs two things: the **R packages** below, and an **alignment
program**. The alignment program (`minimap2`) is already bundled for every
supported platform, so in the normal case there is nothing to install for it.

## 1. What is needed

| Dependency | Type | Required for | How to get it |
|---|---|---|---|
| R packages | R packages | Core analysis | `pak` / `install.packages()` / `BiocManager::install()` — section 3 |
| `minimap2` | external command | Modes A and B (read alignment) | **already bundled** in `03_dependence/<os>-<arch>/bin/` |
| `DECIPHER` | optional R package | Mode B clustering and consensus | section 3 |
| `pwalign` | optional R package | `pairwiseAlignment()` on Bioconductor >= 3.19 | section 3 |
| `samtools` | optional external command | only if you explicitly set `use_samtools = TRUE` | not bundled, not needed: `Rsamtools::asBam()` handles SAM -> BAM |

Mode C (raw exact matching) does not need `minimap2` at all. `samtools` is never
required because `Rsamtools::asBam()` performs the SAM to BAM conversion, which
is why it is not bundled.

## 1.1 Bundled tools and the R-native fallback

`nanoamp` looks for tools in this order:

1. `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS` environment variables;
2. `03_dependence/<os>-<arch>/bin/`;
3. `PATH`.

The repository bundles **minimap2 2.31 for all four supported platforms**:

| Platform | Bundled file | Verified runtime requirement |
|---|---|---|
| linux-x86_64 | `03_dependence/linux-x86_64/bin/minimap2` | glibc >= 2.14, system zlib |
| linux-arm64 | `03_dependence/linux-arm64/bin/minimap2` | glibc >= 2.17, system zlib |
| macos-x86_64 | `03_dependence/macos-x86_64/bin/minimap2` | macOS system libraries only |
| macos-arm64 | `03_dependence/macos-arm64/bin/minimap2` | macOS system libraries only |

Because the binaries link only against OS-provided libraries, a fresh clone works
with no conda, no package manager and no network. Versions, sources and sha256
values are in `03_dependence/manifest.tsv`; the reasoning behind sourcing them
from conda-forge is in `03_dependence/README.md`. Windows dependency material is
owned by the sister repository `a_09_18_26_mapping_programs_dev_for_win`.

If your host does not match any bundled file (for example an old glibc), use the
R-native backend instead of installing anything:

```r
run_haplotype_analysis(..., aligner = "r")
```

`samtools` remains supported as an escape hatch: if it is on `PATH`,
`use_samtools = TRUE` will use it instead of `Rsamtools`.

## 2. Installing minimap2 (usually unnecessary)

Skip this section unless `sh 02_code/cli/nanoamp doctor` reports
`minimap2 NOT FOUND`, which can only happen on a platform other than the four
above or if the bundled file is missing.

To restore the bundled binary on any machine that has `mamba`/`conda`
(cross-platform download works from any host — no emulator or Docker needed):

```bash
bash 03_dependence/fetch_dependencies.sh              # current platform
bash 03_dependence/fetch_dependencies.sh --all         # all four platforms
```

To install minimap2 some other way instead (conda, Homebrew, apt, or your own
build), just make sure it ends up on `PATH`; nanoamp will find it after the
bundled lookup fails.

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

### Automated install (pak first)

`02_code/scripts/install_r_deps.R` installs everything above. It tries
`pak::pak()` first, because pak resolves the CRAN and Bioconductor graph
together and uses the **precompiled binaries** that CRAN and Bioconductor
publish for macOS (arm64 and x86_64) and Windows, which avoids long source
compilations. If pak is missing or fails it falls back to
`install.packages()` + `BiocManager::install()`.

```bash
Rscript 02_code/scripts/install_r_deps.R              # required + optional
Rscript 02_code/scripts/install_r_deps.R --dry-run    # only report what is missing
Rscript 02_code/scripts/install_r_deps.R --only-required
```

### Manual equivalent

If you prefer to drive it yourself, the two commands below are exactly what the
fallback path does:

```r
install.packages(c("data.table", "jsonlite", "optparse", "readxl"))
BiocManager::install(c("Biostrings", "IRanges", "Rsamtools", "ShortRead",
                       "DECIPHER", "pwalign"))
```

Install location used by this repository's local verification environment
(convenient and disposable, since `tmp/` is ignored by Git):

```bash
mamba create -y -p ./tmp/nanoamp-env -c conda-forge -c bioconda \
  r-base \
  r-data.table r-optparse r-jsonlite r-readxl \
  bioconductor-biostrings bioconductor-rsamtools bioconductor-shortread \
  bioconductor-iranges bioconductor-decipher \
  r-testthat r-pkgload
```

Note that `minimap2` is deliberately absent from that list: the bundled binary in
`03_dependence/` is used instead. `tmp/` stays out of the repository.

## 4. Verification checklist

```r
library(nanoamp)
nanoamp_cli("doctor")
```

Expected output — note that `minimap2` resolves **inside the repository**, and
that `samtools` is reported as optional:

```text
nanoamp version: 0.1.0
R version: ...
Rscript: ...
platform: macos-arm64
dependence directory: /path/to/repo/03_dependence
  Biostrings   TRUE
  ...
  DECIPHER     TRUE
  minimap2     /path/to/repo/03_dependence/macos-arm64/bin/minimap2 (2.31-r1302)
  samtools     NOT FOUND (optional; Rsamtools is used by default)
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

1. `minimap2` is bundled for all four supported platforms (linux/macos x
   x86_64/arm64) and links only against OS-provided libraries, so no conda,
   package manager or network access is needed at run time;
2. `Rsamtools::asBam()` performs SAM to BAM conversion by default, so the
   `samtools` command is no longer bundled and is optional;
3. `aligner = "r"` provides an R-native pairwise alignment backend for small
   and medium datasets, and as a fallback when the bundled binary does not fit
   the host (for example a glibc older than 2.14);
4. `minimap2` remains the recommended backend for large datasets.

Set `use_samtools = TRUE` only if you explicitly need the samtools path.
