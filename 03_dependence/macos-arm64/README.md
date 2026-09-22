# macos-arm64 (Apple Silicon)

`bin/minimap2` is bundled (version 2.31-r1302), so Modes A and B work here without
installing anything.

| Property | Value |
|---|---|
| File | `bin/minimap2` (Mach-O 64-bit, arm64) |
| Source | conda-forge `minimap2`, fetched with `CONDA_SUBDIR=osx-arm64` |
| sha256 | `007777300e7f1dc464300135d1b16e5c47bef40ae19a1017c1504d33b2509142` |
| Runtime requirements | only `/usr/lib/libSystem.B.dylib`; the system zlib is taken from the dyld shared cache, so no conda is needed at run time |

This is the binary used for the local verification recorded in
`00_materials/work_reports/work_report.8.md`: the file was copied to an empty
directory and executed with a stripped environment (`env -i`), and it still
printed its version. Re-check with:

```bash
./03_dependence/macos-arm64/bin/minimap2 --version
sh 02_code/cli/nanoamp doctor
```

Refresh the binary:

```bash
bash 03_dependence/fetch_dependencies.sh --platform macos-arm64
```

`samtools` is not bundled: `Rsamtools::asBam()` performs the SAM -> BAM
conversion. Without any external binary you can also use
`run_haplotype_analysis(..., aligner = "r")`.
