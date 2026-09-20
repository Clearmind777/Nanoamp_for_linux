# 05_builds

Build artifacts. Everything here is reproducible and ignored by Git except this
README.

```text
05_builds/
`-- r/
    |-- nanoamp_0.1.0.tar.gz   # R CMD build output
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
