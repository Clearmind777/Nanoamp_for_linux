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
|-- windows-x86_64/
|   |-- README.md
|   |-- install_msys2_toolchain.ps1   # reproducible toolchain installer
|   |-- build_minimap2.sh             # builds minimap2.exe from source
|   `-- bin/minimap2.exe              # built in-repo, statically linked
|-- linux-arm64/README.md
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
| windows-x86_64 | bundled 2.31 (built in-repo) | not bundled | statically linked, runs without MSYS2/Cygwin/conda/WSL; samtools unnecessary because Rsamtools handles SAM -> BAM |
| linux-arm64 | not bundled | not bundled | use conda or build from source; R-native backend available |
| windows-arm64 | no binary | no binary | R-native backend, or run the x86_64 build under emulation |
| macos-x86_64 | not bundled | not bundled | use conda |
| macos-arm64 | not bundled | not bundled | use conda |

Official upstream facts:

- minimap2 publishes a Linux x86_64 binary; there is no *official* Windows or
  ARM binary, but the source builds natively on Windows with the MSYS2
  MINGW-w64 toolchain — that is how `windows-x86_64/bin/minimap2.exe` was made.
- samtools publishes only source; Windows binaries are not officially provided.
  htslib's own `INSTALL` documents Windows MSYS2/MINGW64 as the recommended
  build environment for Windows.
- conda-forge / bioconda provide `samtools` for Linux ARM64, but not for
  Windows; bioconda does not support Windows.

## Windows source build

Windows needs no conda and no WSL. Two unattended steps:

```powershell
# 1. portable MSYS2 + MINGW-w64 toolchain (~1.5 GB, outside the repo)
pwsh -File 03_dependence/windows-x86_64/install_msys2_toolchain.ps1

# 2. build and install minimap2.exe
bash 03_dependence/windows-x86_64/build_minimap2.sh
```

The toolchain itself is not committed (too large); the repository commits the
two scripts above plus the resulting binary and its provenance.
See `windows-x86_64/README.md` for the pinned versions, flags and hashes.

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
