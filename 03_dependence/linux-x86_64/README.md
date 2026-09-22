# linux-x86_64

`bin/minimap2` is bundled (version 2.31-r1302), so Modes A and B work here without
installing anything.

| Property | Value |
|---|---|
| File | `bin/minimap2` (ELF 64-bit, x86-64, PIE) |
| Source | conda-forge `minimap2`, fetched with `CONDA_SUBDIR=linux-64` |
| sha256 | `8a561f2c29f5a250eeecb6915100d23194dd38a41bb230d0b6afe69f78d5adf4` |
| Runtime requirements | glibc >= 2.14 and the system zlib (`libz.so.1`); no conda at run time |

This is the earliest development platform of the repository (see
`00_materials/work_reports/work_report.1.md` .. `work_report.7.md`). The binary
was replaced in report 8: it used to be the upstream
`minimap2-2.31_x64-linux.tar.bz2` release, and now all four platforms come from
conda-forge so they share one version and one build recipe.

The binary links only against `libm`, `libz`, `libpthread` and `libc` (checked
with `file` and the ELF `DT_NEEDED` entries), so any distribution from
CentOS 7 / Ubuntu 16.04 onwards can run it.

```bash
./03_dependence/linux-x86_64/bin/minimap2 --version
sh 02_code/cli/nanoamp doctor
```

Refresh the binary:

```bash
bash 03_dependence/fetch_dependencies.sh --platform linux-x86_64
```

`samtools` is no longer bundled. `Rsamtools::asBam()` performs the SAM -> BAM
conversion, so samtools is optional; if it happens to be on `PATH`,
`use_samtools = TRUE` will use it.
