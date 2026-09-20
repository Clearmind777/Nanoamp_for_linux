# nanoamp

`nanoamp` analyzes Oxford Nanopore reads from PCR amplicons. Given a FASTQ file
and a target sequence, it corrects sequencing errors, reconstructs haplotypes,
and reports the most abundant sequences with counts and proportions.

> **This repository is the Linux-only variant.** Bundled tools, CI and
> documentation all target Linux. Windows-specific material (prebuilt
> `minimap2.exe`, the MSYS2 toolchain and build scripts, the RInno installer
> skeleton, the R environment scripts and the offline installer bundle) lives
> in a separate Windows repository (intended name:
> `a_09_18_26_mapping_programs_dev_for_win`), which is not part of this
> checkout.
>
> This repository is published as `Clearmind777/Nanoamp_for_linux`. The
> original cross-platform development repository is `Clearmind777/nanoamp`.

## Repository layout

```text
00_materials/     project brief, development plan and work reports
01_data/          raw test data and the normalized symlink layer
02_code/          source code
  r/              nanoamp R package
  cli/            standalone R CLI entry points and launchers
  gui/            standalone R Shiny GUI entry points and launchers
  shared/         shared parameter, output and interface contracts
03_dependence/    bundled external tools and the Linux x86_64 offline runtime
04_results/       run outputs (Git ignores everything except README)
05_builds/        R tarballs and R CMD check outputs (Git ignored)
tmp/              scratch space (Git ignored)
```

## Quick start

### Fully offline (Linux x86_64, no R installation required)

```bash
./03_dependence/linux-x86_64/nanoamp doctor
./03_dependence/linux-x86_64/nanoamp call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --outdir 04_results/cli/offline-demo
./03_dependence/linux-x86_64/nanoamp-gui
```

The runtime is stored as 7 split parts (about 573 MB in total). The first run
reassembles them, verifies the SHA256, extracts R 4.4.3 and all R package
dependencies, runs `conda-unpack`, and then executes the analysis.

### Use an existing R installation

```bash
# 1. Install the R package
R CMD INSTALL 02_code/r

# 2. Check the environment (repository launcher)
sh 02_code/cli/nanoamp doctor

# Optional: install a global `nanoamp` command
sh 02_code/cli/install_cli.sh ~/.local/bin

# 3. Run one sample
sh 02_code/cli/nanoamp call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --top-n 20 \
  --outdir 04_results/cli/demo

# 4. Launch the GUI
Rscript 02_code/gui/run_gui.R
```

R console:

```r
library(nanoamp)
res <- run_haplotype_analysis(
  reads     = "01_data/ln_test_data/TSM20260826/E4-3/reads.fastq",
  reference = "01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa",
  outdir    = "04_results/r/demo/E4-3",
  mode      = "A"
)
res$haplotypes
```

## Documentation

| Document | Content |
|---|---|
| `02_code/README.md` | source tree and component status |
| `02_code/r/README.md` | R package tutorial (English) |
| `02_code/r/README-CN.md` | R package tutorial (Chinese) |
| `02_code/r/inst/docs/INSTALL_DEPENDENCIES.md` | minimap2 / samtools installation on Linux |
| `02_code/cli/README.md` | CLI contract and launchers |
| `02_code/gui/README.md` | GUI features and launchers |
| `03_dependence/README.md` | bundled tools and platform support matrix |
| `03_dependence/linux-x86_64/README.md` | offline R runtime: layout, usage and rebuild |
| `00_materials/README.md` | planning documents and work reports |

## External tools

`nanoamp` resolves tools in this order:

1. `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`;
2. `03_dependence/<os>-<arch>/bin/`;
3. `PATH`.

The repository bundles minimap2 2.31 for **Linux x86_64**, plus an optional
samtools 1.12 fallback. Linux ARM64 and macOS have no bundled binary; the fetch
recipes and the platform matrix are in `03_dependence/README.md`.

For Linux x86_64 the repository also bundles a portable R 4.4.3 runtime under
`03_dependence/linux-x86_64/`, so the CLI and GUI can run without installing R.

On platforms without a bundled binary (for example ARM), use the R-native
backend:

```r
run_haplotype_analysis(..., aligner = "r")
```

samtools is optional: SAM to BAM conversion uses `Rsamtools::asBam()` by
default, so no samtools binary is needed on any platform.

## Running the test suite

```bash
# unit tests (uses the bundled/installed minimap2 when available)
make test

# equivalent direct command
Rscript -e 'devtools::test("02_code/r", reporter = "summary", stop_on_failure = TRUE)'

# build and R CMD check into 05_builds/r
make check

# functional regression over the real datasets in 01_data/
Rscript 02_code/r/inst/scripts/run_functional_tests.R \
  --outdir 04_results/r/test_run --modes A,B,C --threads 4
```

The normalised symlink layer in `01_data/ln_test_data/` is checked out as real
symlinks on Linux. If the tree was copied from a Windows checkout and contains
regular files instead, rebuild it with:

```bash
Rscript 02_code/r/inst/scripts/prepare_test_data.R
```

## Common commands

```bash
make install     # install the R package
make test        # run testthat tests and fail on errors
make check       # build and R CMD check
make cli         # run `nanoamp doctor`
make gui         # launch the Shiny GUI
make deps        # fetch external tools where possible
```

## License

MIT.
