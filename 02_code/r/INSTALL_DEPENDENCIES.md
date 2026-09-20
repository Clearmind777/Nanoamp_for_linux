# Installing dependencies for nanoamp

This guide explains how to install and configure `minimap2`, `samtools` and
the R packages required by `nanoamp` on Linux and Windows.

## 1. What is needed

| Dependency | Type | Required for |
|---|---|---|
| `minimap2` | external command | Modes A and B (read alignment) |
| `samtools` | external command | Modes A and B (SAM/BAM sorting and indexing) |
| R packages | R packages | Core analysis |
| `DECIPHER` | optional R package | Mode B de novo clustering |
| `shiny`, `bslib`, `DT` | optional R packages | GUI |

Mode C (raw exact matching) does not need `minimap2` or `samtools`.

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

Then install R packages inside the same R environment (see section 4).

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

## 3. Windows

### Option A: conda / mamba (recommended)

1. Install Miniforge or Miniconda.
2. Open **Miniforge Prompt** or **Anaconda Prompt**.
3. Create an environment with the two tools:

```bat
conda create -n nanoamp -c conda-forge -c bioconda minimap2 samtools
conda activate nanoamp

where minimap2
where samtools
```

4. Install R in the same environment (or use a system R installation):

```bat
conda install -c conda-forge r-base
```

5. Start R or RStudio **from the activated prompt**, or add the environment's
   `Library\bin` and `Scripts` directories to the Windows `PATH`.

Example path:

```text
C:\Users\<you>\miniforge3\envs\nanoamp\Library\bin
C:\Users\<you>\miniforge3\envs\nanoamp\Scripts
```

### Option B: prebuilt binaries

- `minimap2`: download the Windows x64 binary from the official releases page,
  extract `minimap2.exe` to a folder such as `C:\tools\minimap2`.
- `samtools`: official Windows binaries are limited. The reliable options are
  conda (section 3A) or WSL2 (section 3C).
- Add the folder containing the `.exe` files to `PATH`.

### Option C: WSL2

1. Install WSL2 and Ubuntu.
2. Install tools inside WSL with `apt` or conda (section 2).
3. Run the analysis inside WSL. This is a good fallback when native Windows
   binaries are unavailable.

### Configure PATH on Windows

1. Open **System Properties -> Environment Variables**.
2. Edit the `Path` variable.
3. Add the folder that contains `minimap2.exe` and `samtools.exe`.
4. Click OK and **restart RStudio / terminal**.
5. Verify in R:

```r
Sys.which("minimap2")
Sys.which("samtools")
library(nanoamp)
nanoamp_cli("doctor")
```

### Windows pitfalls

- **conda environment not activated**: R started outside the environment will
  not see the tools.
- **PATH not refreshed**: restart RStudio after changing `PATH`.
- **Spaces or non-ASCII characters in paths**: prefer `C:\tools\...`.
- **Windows SmartScreen**: allow the downloaded binaries if prompted.
- **Multiple R installations**: check `Rscript -e 'cat(R.home())'` and make
  sure you install the package into the R you actually use.

## 4. R packages

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
BiocManager::install("DECIPHER")          # Mode B
install.packages(c("shiny", "bslib", "DT"))  # GUI
```

## 5. Verification checklist

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

- `minimap2` and `samtools` show a path, not `NOT FOUND`;
- R packages show `TRUE`;
- `DECIPHER` may be `FALSE`: Mode B still works with a fallback, but DECIPHER
  is recommended.

## 6. Future: reducing external dependencies

Two planned improvements can reduce the dependency burden:

1. use `Rsamtools` (`asBam`, `sortBam`, `indexBam`) instead of the `samtools`
   command;
2. add an R-native alignment backend (`aligner = "r"`) for small and medium
   datasets, keeping `minimap2` for large datasets.
