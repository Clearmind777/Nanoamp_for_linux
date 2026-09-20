# GUI (R Shiny)

The GUI is implemented with R Shiny and shipped inside the `nanoamp` R package.
The Python option has been cancelled; the GUI calls the same R analysis
functions as the CLI.

## Current implementation

```r
library(nanoamp)
nanoamp_gui()
```

The app provides:

- FASTQ and reference FASTA file pickers;
- output directory selection;
- mode selection (A reference-guided, B de novo, C exact);
- `top_n` and advanced parameters;
- run button with progress and captured log;
- interactive haplotype and variant tables (DT);
- download buttons for `haplotypes.tsv` and `variants.tsv`;
- links to the output directory;
- alignment backend selection (`minimap2` or the R-native `r` fallback).

## Launch

After installing the R package and its dependencies:

```bash
Rscript 02_code/gui/run_gui.R
```

Or from R:

```r
library(nanoamp)
nanoamp_gui()
```

The app starts a local Shiny server and opens the default browser.

## Packaging

This Linux-only variant ships no standalone installer: the GUI runs from the
installed R package. Windows installer packaging is owned by the sister
repository `a_09_18_26_mapping_programs_dev_for_win`.

External tools are resolved from `03_dependence/<os>-<arch>/bin/` first; see
`03_dependence/README.md`.

## Required packages

```r
install.packages(c("shiny", "DT"))
```

These are listed in `Suggests` so the core package remains lightweight.
