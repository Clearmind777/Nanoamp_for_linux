#!/bin/sh
# ---------------------------------------------------------------------------
# Fetch the bundled minimap2 binary for nanoamp.
#
# Four platforms are supported and all four are pre-bundled in the repository:
#
#   linux-x86_64   linux-arm64   macos-x86_64   macos-arm64
#
# Usage:
#   bash 03_dependence/fetch_dependencies.sh              # platform detected from uname
#   bash 03_dependence/fetch_dependencies.sh --all         # refresh all four
#   bash 03_dependence/fetch_dependencies.sh --platform macos-arm64
#
# Why the binaries come from conda-forge rather than the upstream release:
#   * upstream publishes an x86_64 Linux build only, so Linux arm64 and both
#     macOS architectures have no official binary;
#   * the conda-forge build needs no conda *at run time*: minimap2 links only
#     libc/libm and the system zlib (verified per platform with `file`, `otool`
#     and `ldd`), so the file can simply be copied next to the repository and
#     executed. That is what makes a pre-bundled binary possible without
#     requiring the user to install conda.
#
# samtools is intentionally NOT bundled: Rsamtools::asBam() performs the
# SAM -> BAM conversion, so samtools is optional. If a machine happens to have
# samtools on PATH, `use_samtools = TRUE` will use it; see 03_dependence/README.md.
#
# Fetching happens on whatever machine runs this script: `mamba`/`conda` can
# download packages for a foreign platform through CONDA_SUBDIR, so a single
# macOS or Linux host can refresh every platform. No emulator or Docker needed.
# ---------------------------------------------------------------------------
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONDA_CHANNELS="-c conda-forge -c bioconda"
MINIMAP2_VERSION="2.31-r1302"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
conda_bin() {
  for c in mamba micromamba conda; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

detect_platform() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$os" in
    darwin) os="macos" ;;
  esac
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
  esac
  echo "${os}-${arch}"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# subdir_for <platform> -> conda subdir name
subdir_for() {
  case "$1" in
    linux-x86_64)  echo "linux-64" ;;
    linux-arm64)   echo "linux-aarch64" ;;
    macos-x86_64)  echo "osx-64" ;;
    macos-arm64)   echo "osx-arm64" ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# fetch_minimap2 <platform>
# ---------------------------------------------------------------------------
fetch_minimap2() {
  platform="$1"
  subdir=$(subdir_for "$platform") || {
    echo "No conda subdir mapped for platform: $platform" >&2
    return 1
  }
  dest="${SCRIPT_DIR}/${platform}/bin"
  mkdir -p "$dest"

  conda=$(conda_bin) || {
    echo "Neither mamba, micromamba nor conda found on PATH." >&2
    echo "Install one of them, or copy a minimap2 binary into ${dest}/ manually." >&2
    return 1
  }

  echo "==> ${platform}: fetching minimap2 (conda subdir ${subdir})"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT INT TERM

  # --no-deps: minimap2 needs no conda-provided shared library, and skipping
  # dependencies keeps the download small.
  CONDA_SUBDIR="$subdir" "$conda" create -y -p "$tmp/env" $CONDA_CHANNELS \
    --no-deps minimap2 >"$tmp/log" 2>&1 || {
      echo "conda fetch failed for ${platform}; log tail:" >&2
      tail -20 "$tmp/log" >&2
      return 1
    }

  src="$tmp/env/bin/minimap2"
  if [ ! -f "$src" ]; then
    echo "minimap2 not found in the fetched environment: $src" >&2
    return 1
  fi

  cp "$src" "$dest/minimap2"
  chmod 755 "$dest/minimap2"
  trap - EXIT INT TERM
  rm -rf "$tmp"

  echo "    installed: ${dest}/minimap2"
  echo "    sha256:    $(sha256_of "$dest/minimap2")"

  # Version check only works for the host platform; foreign binaries are
  # verified with `file` instead.
  host=$(detect_platform)
  if [ "$host" = "$platform" ]; then
    version=$("$dest/minimap2" --version 2>/dev/null || echo '?')
    echo "    version:   ${version}"
  else
    echo "    (foreign platform: not executed here)"
    file -b "$dest/minimap2" 2>/dev/null | sed 's/^/    file:      /' || true
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
MODE="auto"
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --all) MODE="all" ;;
    --platform) shift; TARGET="${1:-}" ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$MODE" = "all" ]; then
  for p in linux-x86_64 linux-arm64 macos-x86_64 macos-arm64; do
    fetch_minimap2 "$p"
  done
elif [ -n "$TARGET" ]; then
  fetch_minimap2 "$TARGET"
else
  host=$(detect_platform)
  echo "Detected platform: ${host}"
  fetch_minimap2 "$host"
fi

echo
echo "Done. nanoamp resolves the binary from 03_dependence/<os>-<arch>/bin/ first."
echo "Check with: sh 02_code/cli/nanoamp doctor"
