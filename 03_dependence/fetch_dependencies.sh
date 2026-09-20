#!/bin/sh
# Fetch bundled external tools for nanoamp (Linux-only variant).
#
# Implemented recipe: linux-x86_64 minimap2 download.
# linux-arm64 and macOS print conda / source instructions.
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64|amd64) ARCH_TAG="x86_64" ;;
  aarch64|arm64) ARCH_TAG="arm64" ;;
  *) ARCH_TAG="$ARCH" ;;
esac

PLATFORM="${OS}-${ARCH_TAG}"
DEST="${SCRIPT_DIR}/${PLATFORM}/bin"
mkdir -p "$DEST"

echo "Detected platform: ${PLATFORM}"

fetch_minimap2_linux_x86_64() {
  VERSION="2.31"
  URL="https://github.com/lh3/minimap2/releases/download/v${VERSION}/minimap2-${VERSION}_x64-linux.tar.bz2"
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  echo "Downloading minimap2 ${VERSION} ..."
  curl -sL --max-time 300 -o "$TMP/minimap2.tar.bz2" "$URL"
  tar xjf "$TMP/minimap2.tar.bz2" -C "$TMP"
  cp "$TMP/minimap2-${VERSION}_x64-linux/minimap2" "$DEST/minimap2"
  chmod +x "$DEST/minimap2"
  "$DEST/minimap2" --version
  echo "Installed: $DEST/minimap2"
}

case "$PLATFORM" in
  linux-x86_64)
    fetch_minimap2_linux_x86_64
    if command -v samtools >/dev/null 2>&1; then
      cp "$(command -v samtools)" "$DEST/samtools"
      chmod +x "$DEST/samtools"
      echo "Copied system samtools to: $DEST/samtools"
      echo "Note: Rsamtools is preferred; samtools is only a fallback."
    fi
    ;;
  linux-arm64)
    cat <<'EOF'
No bundled minimap2 binary for linux-arm64.
Options:
  1. conda create -p 03_dependence/linux-arm64/conda \
       -c conda-forge -c bioconda minimap2 samtools
     then copy bin/minimap2 and bin/samtools to 03_dependence/linux-arm64/bin/
  2. run nanoamp with aligner = "r" (no external tool required)
EOF
    ;;
  darwin-*|macos-*)
    cat <<'EOF'
No bundled macOS binaries.
Recommended:
  conda create -p 03_dependence/macos-<arch>/conda \
    -c conda-forge -c bioconda minimap2 samtools
  then copy bin/minimap2 and bin/samtools to 03_dependence/macos-<arch>/bin/
Alternatively use aligner = "r".
EOF
    ;;
  *)
    echo "No fetch recipe for platform: $PLATFORM"
    echo "Use aligner = \"r\", or place binaries in ${DEST}/ manually."
    ;;
esac
