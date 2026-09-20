# nanoamp

`nanoamp` analyzes Oxford Nanopore reads from PCR amplicons. Given a FASTQ file
and a target sequence, it corrects sequencing errors, reconstructs haplotypes,
and reports the most abundant sequences with counts and proportions.

## Repository layout

```text
00_materials/     project brief, development plan and work reports
01_data/          raw test data and the normalized symlink layer
02_code/          source code
  r/              nanoamp R package
  cli/            standalone R CLI entry points and launchers
  gui/            standalone R Shiny GUI entry points and launchers
  shared/         cross-language parameter and output contracts
03_dependence/    bundled external tools and fetch instructions
04_results/       run outputs (Git ignores everything except README)
05_builds/        R tarballs and R CMD check outputs (Git ignored)
tmp/              scratch space (Git ignored)
```

## Quick start

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
| `02_code/r/inst/docs/INSTALL_DEPENDENCIES.md` | minimap2 / samtools installation on Linux and Windows |
| `02_code/cli/README.md` | CLI contract and launchers |
| `02_code/gui/README.md` | GUI features and Windows packaging |
| `03_dependence/README.md` | bundled tools and platform support matrix |
| `00_materials/README.md` | planning documents and work reports |

## External tools

`nanoamp` resolves tools in this order:

1. `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`;
2. `03_dependence/<os>-<arch>/bin/`;
3. `PATH`.

The repository bundles minimap2 2.31 for Linux x86_64. On platforms without an
official minimap2 binary (Windows, ARM), use the R-native backend:

```r
run_haplotype_analysis(..., aligner = "r")
```

samtools is optional: SAM to BAM conversion uses `Rsamtools::asBam()` by
default.

## Common commands

```bash
make install     # install the R package
make test        # run testthat tests
make check       # build and R CMD check
make cli         # run `nanoamp doctor`
make gui         # launch the Shiny GUI
make deps        # fetch external tools where possible
```

## License

MIT.
