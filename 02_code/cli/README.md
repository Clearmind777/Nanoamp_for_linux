# CLI contract

The CLI is implemented in R and shipped with the `nanoamp` R package. The
Python CLI planned earlier has been cancelled; all CLI development targets the
R implementation.

## Commands

```text
nanoamp call   --reads <fastq> --reference <fasta> --outdir <dir> [--mode A|B|C] [options]
nanoamp batch  --sample-sheet <tsv> --outdir <dir> [--mode A|B|C] [options]
nanoamp doctor
nanoamp help
```

## call options

| Option | Type | Default | Description |
|---|---:|---:|---|
| `--reads` | path | required | Input FASTQ (plain or gz) |
| `--reference` | path | required | Target sequence FASTA |
| `--outdir` | path | required | Output directory |
| `--mode` | string | `A` | A reference-guided, B de novo, C exact |
| `--top-n` | int | 20 | Number of top haplotypes |
| `--min-reads` | int | 3 | Minimum supporting reads per variant |
| `--min-freq` | float | 0.02 | Minimum variant frequency |
| `--min-identity` | float | 0.90 | Minimum read identity |
| `--identity-cutoff` | float | 0.99 | Mode B clustering identity cutoff |
| `--min-cluster-reads` | int | 2 | Mode B minimum cluster size |
| `--consensus-method` | string | `decipher` | `decipher` or `medoid` |
| `--aligner` | string | `minimap2` | `minimap2` or `r` (R-native fallback) |
| `--threads` | int | 4 | Number of threads |
| `--ref-label` | string | reference name | Reference label in outputs |
| `--no-intermediates` | flag | false | Do not keep BAM files |
| `--annotate-config` | path | none | Enable functional annotation with this JSON config |
| `--transcript` | string | none | Transcript id to annotate, or `all` for every overlapping transcript |
| `--list-transcripts` | flag | false | Print the candidate transcripts for the amplicon |
| `--annotation-proteins` | flag | false | Include reference/alternate protein sequences in `annotation.tsv` |
| `--annotation-detail` | flag | false | Also write `variants_annotation.tsv` (per-variant consequences) |
| `--clear-cache` | flag | false | Clear the annotation reference cache and exit |
| `--no-cache` | flag | false | Ignore cached reference slices and re-fetch them |
| `--cache-dir` | path | `$XDG_CACHE_HOME/nanoamp/ref` | Cache location |

### Annotation notes

Annotation is the only part of the CLI that uses the network. It fetches the
transcript structure and sequence slices it needs from Ensembl REST, caches them,
and **fails with a non-zero exit code** when the providers are unreachable --
it never silently returns unannotated results. The `cds` route
(`cds.start` / `cds.end` in the config) works entirely offline.

See the "Functional annotation" section of the root README for the consequence
vocabulary and the self-checks that run on every annotation pass.

The Ensembl release actually used is recorded in `run_manifest.json` as
`annotation.ensembl_release`; quote that value when reporting or re-checking
results. `--ensembl-release` does **not** exist in v0.1.0 — pinning a historical
release needs the Ensembl archive hosts, so it is left for a later version.

## batch input

TSV with at least:

```text
sample	reads	reference
```

Optional column: `ref_label`.

## Installation

### Linux / macOS

```bash
sh "$(Rscript --vanilla -e 'cat(system.file("scripts", "install_cli.sh", package = "nanoamp"))')" ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
nanoamp doctor
```

This installs the wrapper that calls the **installed** package. The repository
also ships a development launcher at `02_code/cli/nanoamp`, which runs straight
from a checkout (it loads `02_code/` with pkgload) and needs no installation.

There is no separate repo-level installer: use this one, or call the launcher
directly. Installing the wrapper from the repository sources would bake a
checkout path into `~/.local/bin`, which breaks as soon as the checkout moves.

## Outputs

`call` writes `haplotypes.tsv`, `haplotypes.fasta`, `variants.tsv`, `qc.tsv` and
`run_manifest.json` into `--outdir`. Field definitions are in
`02_code/shared/docs/output_schema.md`.

## External tools

`minimap2` is resolved from `03_dependence/<os>-<arch>/bin/` first, then from
`PATH`. On platforms without a minimap2 binary, use `--aligner r` to run the
R-native pairwise alignment backend. samtools is optional: SAM -> BAM is
handled by `Rsamtools` by default.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Success |
| 1 | Any error (invalid arguments, missing input, missing dependency, analysis failure) |

The current implementation uses R error handling, so all failures exit with
code 1. More granular exit codes are a future improvement.
