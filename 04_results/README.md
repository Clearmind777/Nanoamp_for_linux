# 04_results

Run outputs. Everything here is reproducible and ignored by Git except this
README.

```text
04_results/
|-- r/                 # R package / CLI test runs
|   `-- test_run_3/    # current canonical functional test
|-- cli/               # CLI smoke examples
`-- _archive/          # older runs kept locally for reference
```

Conventions:

- one subdirectory per run;
- core outputs follow `02_code/shared/docs/output_schema.md`;
- the current functional test is `04_results/r/test_run_3/`;
- older runs are moved to `04_results/_archive/` instead of being deleted;
- build artifacts belong in `05_builds/`, not here.

Current canonical test summary:

```text
04_results/r/test_run_3/
  comparison.tsv
  run_index.tsv
  summary_by_mode.tsv
  functional_test.log
  <dataset>/<sample>/mode_<A|B|C>/<self|wt>/
```
