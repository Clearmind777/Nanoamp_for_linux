# linux-arm64

`bin/minimap2` is bundled (version 2.31-r1302), so Modes A and B work here without
installing anything.

| Property | Value |
|---|---|
| File | `bin/minimap2` (ELF 64-bit, AArch64) |
| Source | conda-forge `minimap2`, fetched with `CONDA_SUBDIR=linux-aarch64` |
| sha256 | `03f361d0b8dba343adb6067fbdc109719196ef0e2619ba02c5295826dcec56dc` |
| Runtime requirements | glibc >= 2.17 and the system zlib (`libz.so.1`); no conda needed at run time |

The binary is verified to link only against `libm`, `libz`, `libpthread`, `libc`
and the dynamic loader (checked with `file` and the ELF `DT_NEEDED` entries). It
was cross-downloaded on a macOS arm64 host, so it is not executed by CI here; if
you are on Linux arm64, confirm with:

```bash
./03_dependence/linux-arm64/bin/minimap2 --version
sh 02_code/cli/nanoamp doctor
```

Refresh or re-fetch the binary on any machine that has conda/mamba (no emulator
needed — `CONDA_SUBDIR` handles the foreign platform):

```bash
bash 03_dependence/fetch_dependencies.sh --platform linux-arm64
```

`samtools` is not bundled: `Rsamtools::asBam()` performs the SAM -> BAM
conversion, so it is optional. Without any external binary at all you can also run
`run_haplotype_analysis(..., aligner = "r")`, which uses the slower R-native
pairwise alignment backend.
