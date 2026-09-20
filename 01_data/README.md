# 01_data

Test data for nanoamp.

```text
01_data/
|-- test_data/       # original company deliverables (do not edit)
|   `-- readme.md     # file-by-file description
`-- ln_test_data/    # normalized symlink layer + manifest.tsv
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

## ln_test_data

A normalized layer of relative symlinks:

```text
ln_test_data/<dataset>/<sample>/
  reads.fastq
  reference.self.fa
  reference.wt.fa
  consensus.N.fa
  variants.N.xlsx
  sanger.N.ab1
  meta.tsv
```

`ln_test_data/manifest.tsv` records the source path of every link.

Regenerate it with:

```bash
Rscript 02_code/r/inst/scripts/prepare_test_data.R
```

The original files under `test_data/` are never modified.
