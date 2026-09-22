# 04_results

Run outputs. Everything here is reproducible and ignored by Git except this
README.

```text
04_results/
|-- r/                      # R package / CLI test runs
|   |-- test_run_3/          # Linux x86_64 functional test (historical)
|   `-- test_run_macos_arm64/  # current canonical functional test (report 8)
|-- cli/                     # CLI smoke examples
`-- _archive/                # older runs kept locally for reference
```

Conventions:

- one subdirectory per run;
- core outputs follow `02_code/shared/docs/output_schema.md`;
- the current functional test is `04_results/r/test_run_macos_arm64/`;
- runs are ignored by Git (`04_results/*` except this README), so they exist only
  on the machine that produced them;
- older runs are moved to `04_results/_archive/` instead of being deleted;
- build artifacts belong in `05_builds/`, not here.

Current canonical test summary (`--modes A,B,C`, all datasets):

```text
04_results/r/test_run_macos_arm64/
  comparison.tsv        # per-run QC + overlap with the company variant tables
  run_index.tsv         # per-run status / elapsed / errors
  summary_by_mode.tsv   # one row per mode
  <dataset>/<sample>/mode_<A|B|C>/<self|wt>/
```

Result of the macOS arm64 run (168/168 runs `ok`):

| mode | runs | ok | mean top1 proportion | mean overlap with company | mean elapsed |
|---|---:|---:|---:|---:|---:|
| A | 56 | 56 | 0.6750 | 0.9807 | 0.22 s |
| B | 56 | 56 | 0.7253 | 0.5409 | 1.06 s |
| C | 56 | 56 | 0.1231 | 0.0000 | 0.11 s |

Reproduce with `make functional-test` (writes to `04_results/r/test_run_local/`).
