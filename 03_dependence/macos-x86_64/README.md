# macos-x86_64 (Intel)

`bin/minimap2` is bundled (version 2.31-r1302), so Modes A and B work here without
installing anything.

| Property | Value |
|---|---|
| File | `bin/minimap2` (Mach-O 64-bit, x86_64) |
| Source | conda-forge `minimap2`, fetched with `CONDA_SUBDIR=osx-64` |
| sha256 | `a051598fff1cea18ce305570dea63e0dd26df6428af2f355e261c90904c1cddc` |
| Runtime requirements | only `/usr/lib/libSystem.B.dylib` and the system zlib; no conda at run time |

The binary links against system libraries only (checked with `otool -L`). It also
runs on Apple Silicon through Rosetta 2, although `03_dependence/macos-arm64/` is
preferred there because it is native.

Verify on an Intel Mac with:

```bash
./03_dependence/macos-x86_64/bin/minimap2 --version
sh 02_code/cli/nanoamp doctor
```

Refresh the binary (cross-fetch works from any host with conda/mamba):

```bash
bash 03_dependence/fetch_dependencies.sh --platform macos-x86_64
```

`samtools` is not bundled: `Rsamtools::asBam()` performs the SAM -> BAM
conversion. Without any external binary you can also use
`run_haplotype_analysis(..., aligner = "r")`.
