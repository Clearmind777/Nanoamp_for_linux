# 03_dependence

External tools bundled with nanoamp. Every supported platform ships a working
`minimap2`, so a fresh clone can run Modes A and B without installing conda or
any other package manager.

## Layout

```text
03_dependence/
|-- README.md / README-CN.md
|-- manifest.tsv                  # version, source and sha256 of every bundled file
|-- fetch_dependencies.sh         # refresh a binary (supports all four platforms)
|-- licenses/
|   `-- minimap2-LICENSE.txt
|-- linux-x86_64/
|   |-- README.md
|   `-- bin/minimap2
|-- linux-arm64/
|   |-- README.md
|   `-- bin/minimap2
|-- macos-x86_64/
|   |-- README.md
|   `-- bin/minimap2
`-- macos-arm64/
    |-- README.md
    `-- bin/minimap2
```

All Windows-specific material (windows-x86_64, windows-arm64, the MSYS2 build
scripts and the R environment scripts) lives in the sister repository
`a_09_18_26_mapping_programs_dev_for_win`.

## Platform support matrix

| Platform | Binary in repo | File format | Runtime requirement |
|---|---|---|---|
| linux-x86_64 | `linux-x86_64/bin/minimap2` | ELF x86-64 | glibc >= 2.14, system zlib |
| linux-arm64 | `linux-arm64/bin/minimap2` | ELF AArch64 | glibc >= 2.17, system zlib |
| macos-x86_64 | `macos-x86_64/bin/minimap2` | Mach-O x86_64 | macOS system libraries only |
| macos-arm64 | `macos-arm64/bin/minimap2` | Mach-O arm64 | macOS system libraries only |

All four are minimap2 2.31-r1302. The total size of the bundled tools is about
2.6 MB. Exact versions, download sources and sha256 values are in
`manifest.tsv`; each platform directory has its own README with the verification
command.

## Why the binaries come from conda-forge

Upstream minimap2 publishes an x86_64 Linux binary only, so Linux arm64 and both
macOS architectures have no official build. conda-forge builds minimap2 for all
four, and — this is the part that makes bundling possible — that build does not
need conda at run time:

- Linux: it links only `libm`, `libz`, `libpthread` and `libc`, with a glibc
  baseline of 2.14 (x86_64) / 2.17 (arm64);
- macOS: it links `/usr/lib/libSystem.B.dylib` plus the system zlib, which dyld
  serves from the shared cache.

Both facts were checked per platform with `file`, the ELF `DT_NEEDED` entries and
`otool -L`, and the macOS arm64 file was additionally executed from `/tmp` with a
stripped environment (`env -i`) to prove it runs outside conda.

`samtools` is deliberately **not** bundled: `Rsamtools::asBam()` performs the
SAM -> BAM conversion, so samtools is optional. If a machine already has samtools
on `PATH`, `use_samtools = TRUE` will use it.

## How nanoamp finds external tools

Resolution order:

1. environment variable `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`;
2. `03_dependence/<os>-<arch>/bin/<tool>`;
3. `PATH`.

`NANOAMP_DEPENDENCE_DIR` can point to a different `03_dependence` location
(useful after installing the R package).

`nanoamp doctor` prints the detected platform, the dependence directory, and the
resolved path and version of each tool. With a bundled binary in place it looks
like this, with no conda on `PATH`:

```text
platform: macos-arm64
dependence directory: /path/to/repo/03_dependence
  minimap2     /path/to/repo/03_dependence/macos-arm64/bin/minimap2 (2.31-r1302)
  samtools     NOT FOUND (optional; Rsamtools is used by default)
```

## R-native fallback

`run_haplotype_analysis(..., aligner = "r")` uses Biostrings/pwalign pairwise
alignment and needs no external binary. It is slower than minimap2 and is
intended for small and medium amplicons, and as a fallback on any platform whose
bundled binary does not fit the host (for example a very old glibc).

## Fetching or updating tools

```bash
bash 03_dependence/fetch_dependencies.sh                  # host platform
bash 03_dependence/fetch_dependencies.sh --all             # all four platforms
bash 03_dependence/fetch_dependencies.sh --platform macos-arm64
```

`mamba`, `micromamba` or `conda` must be available, but only to *fetch*: the
script uses `CONDA_SUBDIR` to download foreign-platform packages, so one macOS or
Linux host can refresh every platform without an emulator or Docker. The fetched
`minimap2` is copied into `03_dependence/<platform>/bin/` and its sha256 is
printed so `manifest.tsv` can be updated.

## Licenses

- minimap2: MIT (license text in `licenses/minimap2-LICENSE.txt`).
