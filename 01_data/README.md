# 01_data

Test data for nanoamp.

```text
01_data/
|-- test_data/       # original company deliverables (never modified)
|   `-- readme.md    # file-by-file description
`-- manifest.tsv     # logical name (dataset/sample/role) -> real file in test_data/
```

## test_data

Original nanopore amplicon deliverables from several batches:

```text
SD260728184122_1/
SD260812174403_1/
TSM20260826-020-01254/
ZNF8/
nano_seq/
```

See `test_data/readme.md` for the meaning of every file type.

## manifest.tsv

Company file names are long (`E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq`).
`manifest.tsv` maps short logical names onto those real files:

| Column | Meaning |
|---|---|
| `dataset` | Logical dataset: `TSM20260826`, `ZNF8`, `nano_seq` |
| `sample` | Logical sample: `E4-3`, `clone_3`, `WT`, ... |
| `role` | `reads`, `reference.self`, `reference.wt`, `consensus`, `variants`, `sanger` |
| `cluster` | Company cluster number (only for `consensus` / `variants` / `sanger`) |
| `path` | Real file path, relative to `01_data/` |
| `source_note` | Where the mapping comes from |

Example lookup — the E4-3 sample:

```bash
awk -F'\t' '$1=="TSM20260826" && $2=="E4-3"' 01_data/manifest.tsv
```

```r
m <- data.table::fread("01_data/manifest.tsv")
m[dataset == "TSM20260826" & sample == "E4-3"][, .(role, cluster, path)]
```

The manifest stores **no data**: every `path` points at the original company
file in `test_data/`. Earlier revisions of this repository kept a parallel
`ln_test_data/` tree of symlinks with the short names; it was byte-identical to
`test_data/` and has been removed, so there is now exactly one copy of every
file.

Regenerate the manifest (it never modifies `test_data/`):

```bash
Rscript 02_code/scripts/prepare_test_data.R
# or: make test-data
```

Consumers of the manifest: `02_code/scripts/run_functional_tests.R` resolves all
inputs through it, and `02_code/tests/testthat/test-core.R` asserts that every
`path` exists.
