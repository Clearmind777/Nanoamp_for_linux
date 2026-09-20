# 02_code: Source Code

This directory is organized as "shared contracts + per-language implementations
+ per-delivery front ends". The R implementation is complete; Python, CLI and
GUI have reserved locations.

```text
02_code/
|-- shared/                 # Cross-language parameters and output schema
|   |-- params/default_params.json
|   `-- docs/output_schema.md
|-- r/                      # R package (available)
|   |-- R/
|   |-- inst/scripts/
|   |-- tests/
|   |-- DESCRIPTION
|   `-- README.md / README-CN.md
|-- python/                 # Python implementation (placeholder)
|-- cli/                    # CLI contract and wrappers
`-- gui/                    # Windows GUI (planned)
```

## Design principles

1. **One algorithm, thin front ends**: GUI and Web call the CLI or the core
   library instead of reimplementing the analysis.
2. **Shared contracts**: parameter names, defaults and output columns are
   defined once in `shared/` and reused by every implementation.
3. **Data and code are separate**: test data lives in `01_data/`; run outputs
   live in `04_results/<language>/`.
4. **Each language is self-contained**: the R package is `02_code/r`; the
   future Python package will live in `02_code/python`.

## R package quick start

```bash
# Install the package
R CMD INSTALL 02_code/r

# Check the environment
nanoamp doctor

# Run one sample
nanoamp call \
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

Full tutorial: `02_code/r/README.md` (English) and `02_code/r/README-CN.md`
(Chinese).

## Status

| Component | Status |
|---|---|
| R package | Implemented and verified with `R CMD check` (`Status: OK`) |
| CLI based on R | Implemented (`nanoamp call` / `batch` / `doctor`) |
| Python package | Placeholder |
| Windows GUI | Planned |

## Shared contracts

- `shared/params/default_params.json`: parameter names and defaults;
- `shared/docs/output_schema.md`: output file and column definitions;
- `cli/README.md`: CLI command contract.
