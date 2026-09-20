# 02_code: Source Code

This directory contains the `nanoamp` R package and the R-based command line
interface. This Linux repository ships the CLI only.

```text
02_code/
|-- README.md / README-CN.md
|-- shared/                 # Parameter and output contracts
|   |-- params/default_params.json
|   `-- docs/output_schema.md
|-- r/                      # nanoamp R package
|   |-- DESCRIPTION / NAMESPACE / LICENSE
|   |-- R/
|   |-- inst/
|   |   |-- docs/           # dependency installation guides
|   |   `-- scripts/        # run_analysis.R, CLI and test scripts
|   |-- tests/testthat/
|   |-- exec/nanoamp        # package CLI wrapper
|   |-- man/                # generated help
|   `-- README.md / README-CN.md
`-- cli/                    # repository CLI entry points and launchers
```

The Python implementation and the graphical interface are out of scope for this
repository; development here targets the Linux CLI. External tools are bundled
under `03_dependence/` at the repository root.

## Design principles

1. **One algorithm, thin front end**: the CLI calls the `nanoamp` R package
   instead of reimplementing the analysis.
2. **Shared contracts**: parameter names, defaults and output columns are
   defined once in `shared/`.
3. **Data and code are separate**: test data lives in `01_data/`; run outputs
   live in `04_results/`.
4. **Bundled tools first**: external tools are resolved from
   `03_dependence/<os>-<arch>/bin/` before `PATH`.

## Quick start

```bash
# Install the package
R CMD INSTALL 02_code/r

# Check the environment (repository launcher)
sh 02_code/cli/nanoamp doctor

# Run one sample
sh 02_code/cli/nanoamp call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --top-n 20 \
  --outdir 04_results/r/demo/E4-3
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

## Status

| Component | Status |
|---|---|
| R package | Implemented and verified with `R CMD check` (`Status: OK`) |
| R-based CLI | Implemented (`nanoamp_cli()` and `02_code/cli`) |

External tools are bundled under `03_dependence/`; see `03_dependence/README.md`
for the platform support matrix and the R-native fallback.

## Shared contracts

- `shared/params/default_params.json`: parameter names and defaults;
- `shared/docs/output_schema.md`: output file and column definitions;
- `cli/README.md`: CLI command contract.
