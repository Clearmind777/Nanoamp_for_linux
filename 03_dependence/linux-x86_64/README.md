# Bundled Linux x86_64 runtime

This directory makes the Linux repository self-contained for x86_64 systems.

## Contents

```text
linux-x86_64/
|-- bin/                    # minimap2 and samtools binaries
|-- nanoamp-r-runtime.tar.gz.part*  # portable R 4.4 runtime (split, <100MB each)
|-- nanoamp-r-runtime.tar.gz.sha256 # checksum of the reassembled tarball
|-- nanoamp                 # CLI wrapper (extracts the runtime on first use)
|-- nanoamp-gui             # Shiny GUI wrapper
|-- activate.sh             # source this to use the runtime interactively
|-- build_runtime.sh        # rebuild the runtime from conda + Bioconductor
`-- README.md
```

The runtime tarball contains:

- R 4.4;
- core R packages: `data.table`, `optparse`, `jsonlite`, `readxl`, `Matrix`;
- Bioconductor packages: `Biostrings`, `Rsamtools`, `ShortRead`, `IRanges`,
  `GenomicAlignments`, `DECIPHER`;
- GUI packages: `shiny`, `DT`;
- `minimap2` and `samtools` inside the runtime `bin/`.

The repository-level `bin/` also carries standalone minimap2 and samtools
binaries, so the resolver works even without unpacking the R runtime.

## Usage

```bash
# CLI
./03_dependence/linux-x86_64/nanoamp doctor
./03_dependence/linux-x86_64/nanoamp call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --outdir 04_results/cli/demo

# GUI
./03_dependence/linux-x86_64/nanoamp-gui

# Interactive shell
source 03_dependence/linux-x86_64/activate.sh
Rscript -e 'library(nanoamp); nanoamp_version()'
```

The runtime is split into <100MB parts so it can be committed with plain Git.
The first invocation reassembles the parts into `nanoamp-r-runtime.tar.gz`,
verifies the SHA256, extracts it into `nanoamp-r-runtime/` and runs
`conda-unpack`. The reassembled tarball and the extracted directory are ignored
by Git.

## Rebuilding

On a Linux x86_64 machine with conda/mamba, `conda-pack` and network access:

```bash
bash 03_dependence/linux-x86_64/build_runtime.sh
```

The script rebuilds the conda environment, installs the Bioconductor packages
and the local `nanoamp` package, prunes documentation and static libraries,
and writes a new runtime tarball plus its SHA256 checksum.
