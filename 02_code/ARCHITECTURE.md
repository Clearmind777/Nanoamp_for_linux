# 02_code: Source Code

`02_code/` is both the repository's code root and the root of the `nanoamp` R
package: `R CMD INSTALL 02_code` works directly. Alongside the package files it
also holds the command line launchers, the shared contracts and the
repository-level helper scripts, which are excluded from the built tarball via
`.Rbuildignore`.

```text
02_code/
|-- DESCRIPTION / NAMESPACE / LICENSE / nanoamp.Rproj   # R package root (flattened)
|-- R/                      # nanoamp R package sources
|-- tests/testthat/         # unit tests
|-- man/                    # generated help
|-- exec/nanoamp            # package CLI wrapper (installed as bin/nanoamp)
|-- inst/
|   |-- docs/               # dependency installation guides
|   `-- scripts/            # CLI entry point + CLI installer shipped with the package
|-- cli/                    # repository CLI entry points and launchers
|-- shared/                 # parameter and output contracts
|   |-- params/default_params.json
|   `-- docs/output_schema.md
|-- scripts/                # repository-level helpers (NOT part of the package)
|   |-- prepare_test_data.R
|   |-- run_analysis.R
|   `-- run_functional_tests.R
|-- README.md / README-CN.md           # package usage
`-- ARCHITECTURE.md / ARCHITECTURE-CN.md   # this file: layout and contracts
```

Why the package is not nested one level deeper: this repository is not a plain R
package, it is a CLI distribution that contains one. Keeping `DESCRIPTION` and
`R/` at the top of `02_code/` removes a redundant directory layer while leaving
`R CMD INSTALL 02_code` as the single install command.

The Python implementation and the graphical interface are out of scope for this
repository; development here targets the CLI. GUI code, the Shiny app and the
Windows installers were removed in an earlier revision and now live only in the
sister repository `a_09_18_26_mapping_programs_dev_for_win`. External tools are
bundled under `03_dependence/` at the repository root.

## Design principles

1. **One algorithm, thin front end**: the CLI calls the `nanoamp` R package
   instead of reimplementing the analysis.
2. **Shared contracts**: parameter names, defaults and output columns are
   defined once in `shared/`.
3. **Data and code are separate**: test data lives in `01_data/`; run outputs
   live in `04_results/`.
4. **Bundled tools first**: external tools are resolved from
   `03_dependence/<os>-<arch>/bin/` before `PATH`.
5. **No duplicate data**: `01_data/manifest.tsv` names the original files in
   `01_data/test_data/` instead of copying or linking them.

## Quick start

```bash
# Install the package
R CMD INSTALL 02_code

# Check the environment (repository launcher)
sh 02_code/cli/nanoamp doctor

# Resolve one sample's real paths from the manifest
Rscript -e 'm <- data.table::fread("01_data/manifest.tsv");
  print(m[dataset=="TSM20260826" & sample=="E4-3", .(role, path)])'

# Run one sample
sh 02_code/cli/nanoamp call \
  --reads 01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq \
  --reference 01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.1.seq \
  --mode A --top-n 20 \
  --outdir 04_results/r/demo/E4-3
```

R console:

```r
library(nanoamp)
res <- run_haplotype_analysis(
  reads     = "01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq",
  reference = "01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.1.seq",
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
