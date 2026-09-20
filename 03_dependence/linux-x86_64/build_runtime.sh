#!/bin/bash
# Build the portable Linux x86_64 runtime bundle.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BUILD="$ROOT/03_dependence/build"
ENV="$BUILD/nanoamp-r-env"
TARBALL="$HERE/nanoamp-r-runtime.tar.gz"

mkdir -p "$BUILD"
rm -rf "$ENV"

echo "Creating conda environment..."
mamba create -p "$ENV" -y -c conda-forge -c bioconda \
  'r-base=4.4' r-biocmanager r-data.table r-optparse r-jsonlite r-readxl \
  r-matrix r-shiny r-dt r-testthat minimap2 samtools pkg-config zlib bzip2 \
  xz libcurl openssl libxml2 libpng libtiff cairo freetype fontconfig \
  harfbuzz fribidi libdeflate libuv

echo "Installing Bioconductor packages..."
"$ENV/bin/Rscript" -e 'options(repos = c(CRAN = "https://cloud.r-project.org"), Ncpus = 4, download.file.method = "libcurl"); BiocManager::install(c("Biostrings", "Rsamtools", "ShortRead", "IRanges", "GenomicAlignments", "DECIPHER"), ask = FALSE, update = FALSE, Ncpus = 4)'

echo "Installing nanoamp..."
"$ENV/bin/R" CMD INSTALL --library="$ENV/lib/R/library" "$ROOT/02_code/r"

echo "Pruning documentation and static libraries..."
rm -rf "$ENV/include" "$ENV/share/doc" "$ENV/share/man" "$ENV/share/info" 2>/dev/null || true
find "$ENV/lib/R/library" -type d -name help -prune -exec rm -rf {} + 2>/dev/null || true
find "$ENV/lib/R/library" -type d -name html -prune -exec rm -rf {} + 2>/dev/null || true
find "$ENV" -name '*.a' -delete 2>/dev/null || true
find "$ENV" -name '*.la' -delete 2>/dev/null || true

echo "Packing runtime..."
conda pack -p "$ENV" -o "$TARBALL" --ignore-missing-files
sha256sum "$TARBALL" > "$TARBALL.sha256"
rm -f "$TARBALL".part*
split -b 95M -d -a 2 "$TARBALL" "$TARBALL.part"
ls -lh "$TARBALL"
ls -lh "$TARBALL".part* | tail -3
