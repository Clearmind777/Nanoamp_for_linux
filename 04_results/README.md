# 04_results

Run outputs. Everything here is reproducible and ignored by Git except this
README.

```text
04_results/
|-- r/                        # R package / CLI test runs
|   |-- test_run_3/            # Linux x86_64 functional test (historical)
|   |-- test_run_macos_arm64/  # macOS arm64, conda-provided minimap2 (report 8)
|   |-- test_run_bundled/      # macOS arm64, pre-bundled minimap2 (report 9)
|   `-- round2/                # macOS arm64, latest regression run (reports 11-12)
|-- cli/                       # CLI smoke examples
`-- _archive/                  # older runs kept locally for reference
    `-- r/                     # 39 earlier runs from the verification rounds
```

Conventions:

- one subdirectory per run;
- core outputs follow `02_code/shared/docs/output_schema.md`;
- the current functional test is `04_results/r/test_run_bundled/`, which exercises
  the pre-bundled `03_dependence/<platform>/bin/minimap2`;
- runs are ignored by Git (`04_results/*` except this README), so they exist only
  on the machine that produced them;
- older runs are moved to `04_results/_archive/` instead of being deleted;
- build artifacts belong in `05_builds/`, not here.

Current canonical test summary (`--modes A,B,C`, all datasets):

```text
04_results/r/test_run_bundled/
  comparison.tsv        # per-run QC + overlap with the company variant tables
  run_index.tsv         # per-run status / elapsed / errors
  summary_by_mode.tsv   # one row per mode
  <dataset>/<sample>/mode_<A|B|C>/<self|wt>/
```

Result of the macOS arm64 runs (168/168 runs `ok`). `test_run_macos_arm64`
(report 8) used a conda-provided minimap2, `test_run_bundled` (report 9) used the
pre-bundled binary; the numbers agree, which is the point of keeping both:

| mode | runs | ok | mean top1 proportion | mean overlap with company | mean elapsed |
|---|---:|---:|---:|---:|---:|
| A | 56 | 56 | 0.6750 | 0.9807 | 0.21-0.22 s |
| B | 56 | 56 | 0.7246-0.7253 | 0.5409 | 1.04-1.06 s |
| C | 56 | 56 | 0.1231 | 0.0000 | 0.11 s |

Reproduce with `make functional-test` (writes to `04_results/r/test_run_local/`).

`round2` is the most recent full regression run: 168/168 runs `ok`, with Mode A
`0.6750` / `0.9807` and Mode C `0.1231` matching the established baseline.
Annotation runs were used during development and live in
`_archive/r/`; they are not part of the canonical regression.
