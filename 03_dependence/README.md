# 03_dependence

External tools bundled with nanoamp.

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
|-- windows-x86_64/README.md
|-- windows-arm64/README.md
|-- macos-x86_64/README.md
`-- macos-arm64/README.md
```

## How nanoamp finds external tools

Resolution order:

1. environment variable `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`;
2. `03_dependence/<os>-<arch>/bin/<tool>` (`<tool>.exe` on Windows);
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
| windows-x86_64 | no official binary | no official binary | use `aligner = "r"` or WSL2 |
| windows-arm64 | no official binary | no official binary | same as windows-x86_64 |
| macos-x86_64 | not bundled | not bundled | use conda |
| macos-arm64 | not bundled | not bundled | use conda |

Official upstream facts:

- minimap2 publishes a Linux x86_64 binary; there is no official Windows or
  ARM binary.
- samtools publishes source code; Windows binaries are not officially provided.
- conda-forge / bioconda provide `samtools` for Linux ARM64, but not for
  Windows.

## R-native fallback

`run_haplotype_analysis(..., aligner = "r")` uses Biostrings pairwise
alignment and needs no external binary. It is slower than minimap2 and is
intended for small and medium amplicons, and for platforms where no minimap2
binary exists (Windows, ARM).

`aligner = "minimap2"` is the default for Linux x86_64.

samtools is no longer required: `Rsamtools::asBam()` converts minimap2 SAM to
BAM. Set `use_samtools = TRUE` only if you explicitly want the samtools path.

## Fetching or updating tools

```bash
bash 03_dependence/fetch_dependencies.sh
```

The script downloads the official minimap2 Linux x86_64 binary and prints
platform-specific instructions for Linux ARM64, Windows and macOS.

## Licenses

- minimap2: MIT;
- samtools: MIT/Expat.

License text for the bundled minimap2 binary is in `licenses/`.
