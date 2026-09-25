# 05_builds

Build artifacts. Everything here is reproducible and ignored by Git except this
README.

```text
05_builds/
`-- r/
    |-- nanoamp_<version>.tar.gz   # R CMD build output
    `-- nanoamp.Rcheck/        # R CMD check output
```

Rebuild with:

```bash
make check
```

Clean build artifacts with:

```bash
make clean-builds
```

The tarball contains the R package only: `02_code/cli`, `02_code/shared`,
`02_code/scripts` and `02_code/configs` are repository-level material and are
excluded through `02_code/.Rbuildignore`.
