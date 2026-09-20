# nanoamp

`nanoamp` analyzes Oxford Nanopore reads from PCR amplicons. Given a FASTQ file
and a target sequence, it corrects sequencing errors, reconstructs haplotypes,
and reports the most abundant sequences with counts and proportions.

This repository is the Linux command-line distribution of `nanoamp`. It ships
the `nanoamp` R package, the `nanoamp` CLI, and the bundled Linux x86_64
`minimap2` / `samtools` binaries. A graphical interface is not part of this
repository.

## Installation

All external dependencies are installed with conda.

```bash
# 1. Create the environment (R, R packages, minimap2 and samtools)
conda create -n nanoamp -c conda-forge -c bioconda \
  r-base minimap2 samtools \
  r-data.table r-optparse r-jsonlite r-readxl \
  bioconductor-biostrings bioconductor-rsamtools bioconductor-shortread \
  bioconductor-iranges bioconductor-decipher
conda activate nanoamp

# 2. Install the nanoamp package bundled in this repository
R CMD INSTALL 02_code/r

# 3. Verify the installation
sh 02_code/cli/nanoamp doctor
```
