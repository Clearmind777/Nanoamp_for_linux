# 03_dependence

External tools bundled with nanoamp (Linux-only variant).

## Layout

```text
03_dependence/
|-- README.md
|-- README-CN.md
|-- manifest.tsv
|-- fetch_dependencies.sh
|-- licenses/
|   `-- minimap2-LICENSE.txt
|-- linux-x86_64/bin/
|   |-- minimap2
|   `-- samtools          # optional fallback
|-- linux-arm64/README.md
|-- macos-x86_64/README.md
`-- macos-arm64/README.md
```

All Windows-specific material (windows-x86_64, windows-arm64, the MSYS2 build
scripts, the R environment scripts and the offline bundle) lives in the sister
repository `a_09_18_26_mapping_programs_dev_for_win`.

## How nanoamp finds external tools

Resolution order:

1. environment variable `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`;
2. `03_dependence/<os>-<arch>/bin/<tool>`;
3. `PATH`.

`NANOAMP_DEPENDENCE_DIR` can point to a different `03_dependence` location
(useful after installing the R package).

`nanoamp doctor` prints the detected platform, the dependence directory, and
the resolved path and version of each tool.

## Platform support matrix

| Platform | minimap2 | samtools | Notes |
|---|---|---|---|
| linux-x86_64 | bundled 2.31 | bundled 1.12 (optional) | Rsamtools is used for SAM -> BAM by default; samtools only with `use_samtools = TRUE` |
| linux-arm64 | not bundled | not bundled | use conda or build from source; R-native backend available |
| macos-x86_64 | not bundled | not bundled | use conda |
| macos-arm64 | not bundled | not bundled | use conda |

Windows has no rows here: `windows-x86_64` / `windows-arm64` are owned by the
sister repository `a_09_18_26_mapping_programs_dev_for_win`, which bundles its
own statically linked minimap2 binary.

Official upstream facts:

- minimap2 publishes a Linux x86_64 binary; there is no official binary for
  Linux ARM64 or macOS, where conda or a source build is the usual route.
- samtools publishes only source; conda-forge / bioconda provide it for Linux
  and macOS, so `samtools` is a conda install away there.

## R-native fallback

`run_haplotype_analysis(..., aligner = "r")` uses Biostrings pairwise
alignment and needs no external binary. It is slower than minimap2 and is
intended for small and medium amplicons, and for platforms where no minimap2
binary exists (Linux ARM64, macOS).

`aligner = "minimap2"` is the default for Linux x86_64.

samtools is no longer required: `Rsamtools::asBam()` converts minimap2 SAM to
BAM. Set `use_samtools = TRUE` only if you explicitly want the samtools path.

## Fetching or updating tools

```bash
bash 03_dependence/fetch_dependencies.sh
```

The script downloads the official minimap2 Linux x86_64 binary and prints
platform-specific instructions for Linux ARM64 and macOS.

## Licenses

- minimap2: MIT;
- samtools: MIT/Expat.

License text for the bundled minimap2 binary is in `licenses/`.

## Offline runtime for Linux x86_64

`linux-x86_64/nanoamp-r-runtime.tar.gz.part*` contains a portable R 4.4.3
runtime with all required R packages and the `nanoamp` package:

- core R packages: `data.table`, `optparse`, `jsonlite`, `readxl`, `Matrix`;
- Bioconductor: `Biostrings`, `Rsamtools`, `ShortRead`, `IRanges`,
  `GenomicAlignments`, `DECIPHER`;
- GUI: `shiny`, `DT`;
- `minimap2` and `samtools`.

The runtime is split into 7 parts (<100 MB each). The first invocation of
`linux-x86_64/nanoamp` or `linux-x86_64/nanoamp-gui` reassembles the parts,
verifies the SHA256, extracts the runtime and runs `conda-unpack`.

```bash
# No R installation required
./03_dependence/linux-x86_64/nanoamp doctor
./03_dependence/linux-x86_64/nanoamp call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --outdir 04_results/cli/offline-demo
./03_dependence/linux-x86_64/nanoamp-gui
```

Rebuild the runtime on a Linux x86_64 machine with network access:

```bash
bash 03_dependence/linux-x86_64/build_runtime.sh
```
