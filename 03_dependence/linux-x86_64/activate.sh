#!/bin/sh
# Source this file (bash/zsh) to use the bundled R runtime.
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
HERE=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
RUNTIME="$HERE/nanoamp-r-runtime"
TARBALL="$HERE/nanoamp-r-runtime.tar.gz"

if [ ! -f "$TARBALL" ]; then
  echo "Reassembling bundled R runtime..." >&2
  cat "$HERE"/nanoamp-r-runtime.tar.gz.part* > "$TARBALL"
fi
if [ -f "$TARBALL.sha256" ]; then
  EXPECTED=$(cut -d' ' -f1 "$TARBALL.sha256")
  ACTUAL=$(sha256sum "$TARBALL" | cut -d' ' -f1)
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "Runtime checksum mismatch" >&2
    return 1 2>/dev/null || exit 1
  fi
fi
if [ ! -x "$RUNTIME/bin/Rscript" ]; then
  mkdir -p "$RUNTIME"
  tar -xzf "$TARBALL" -C "$RUNTIME"
  if [ -x "$RUNTIME/bin/conda-unpack" ]; then
    "$RUNTIME/bin/conda-unpack"
  fi
fi

export NANOAMP_DEPENDENCE_DIR="$ROOT/03_dependence"
export R_HOME="$RUNTIME/lib/R"
export R_LIBS_USER="$RUNTIME/lib/R/library"
export PATH="$RUNTIME/bin:$HERE/bin:$PATH"

echo "nanoamp runtime activated: $RUNTIME"
