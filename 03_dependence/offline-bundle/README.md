# offline-bundle — pre-positioning the installers inside the project

Answering the question "can R, the build toolchain and the external tools all be
pre-positioned in the project?":

**Technically yes, and it is now implemented and verified — but the installers
must not be committed to Git.** This directory holds the scripts; the artifacts
themselves live in `dist/`, which is git-ignored.

## What "already self-contained" vs "still needs installing" means here

| Piece | Size | Status |
|---|---:|---|
| `minimap2.exe` | 1.3 MB | **already committed** — Windows analysis works out of the box |
| samtools | — | **not needed** — `Rsamtools::asBam()` is the default SAM -> BAM path |
| R runtime + 109 R packages | ~430 MB | must be installed (or provisioned from `dist/`) |
| MSYS2 + MINGW-w64 toolchain | ~1.5 GB installed / 51 MB tarball | only needed to *rebuild* minimap2 from source |

So an end user needs R plus the package library. A developer who wants to
rebuild minimap2 additionally needs the toolchain.

## What the bundle contains

`fetch_offline_bundle.R` downloads, into `dist/`:

```text
dist/
|-- R-4.6.1-win.exe                   87.5 MB   R installer
|-- r-packages/
|   `-- bin/windows/contrib/4.6/       ~200 MB   109 package .zip files
|       |-- *.zip                                plus a PACKAGES index
|       `-- PACKAGES
|-- msys2/
|   `-- msys2-base-x86_64-20250830.tar.zst  51.3 MB   toolchain for rebuilds
|-- src/
|   `-- minimap2-2.31.tar.gz           0.3 MB   minimap2 source
|-- SOURCES.tsv                        provenance + SHA256 per file
`-- SHA256SUMS.txt                     integrity manifest
```

Total: **291 MB**, reproducible and pinned.

The package set is not a hand-written list. The script resolves the recursive
`Depends` / `Imports` / `LinkingTo` closure and then iterates until the closure
closes (new packages bring their own dependencies — e.g. `futile.logger` pulls
in `lambda.r` and `futile.options`). It finishes at 109 packages and reports
`complete`, or prints exactly what is still missing.

## Usage

```powershell
# on a machine WITH a network: build the bundle
Rscript 03_dependence/offline-bundle/fetch_offline_bundle.R

# on a machine WITHOUT a network: install everything from it
pwsh -File 03_dependence/offline-bundle/install_offline.ps1
```

`install_offline.ps1` verifies every file against `SHA256SUMS.txt`, installs R
silently as the current user (no administrator rights), installs all bundled
packages from the local repository, installs `nanoamp`, repairs the test-data
link layer and runs the test suite. It never touches the network.

## Verified offline

Tests run with `http_proxy`/`https_proxy` pointed at a dead port, so any network
attempt fails immediately, and with only the bundle-provided library visible:

```text
bundle packages visible      : 109
installed package dirs       : 109
nanoamp CMD INSTALL          : DONE
testthat                     : 34 passed, 0 failed, 0 errors, 0 skipped
functional (Mode A, E4-3)    : 2/2 ok, mean_overlap 1.0
```

## Why the artifacts are not committed to Git

This is the part worth being explicit about.

1. **Hard file-size limits.** GitHub rejects any push containing a file over
   100 MiB and warns above 50 MiB. The R installer is 87.5 MB — under the hard
   limit but close enough that it would be refused outright on most other
   hosts, and it would be blocked the moment R ships a slightly larger build.
2. **History is permanent.** `git rm` does not reclaim the space; the blobs stay
   in history forever. A 291 MB bundle would make every future clone pay for it,
   permanently, on top of the 65 MB the repository already needs.
3. **Git LFS is not a free escape.** The free tier is 1 GB of storage and 1 GB
   of monthly bandwidth; a 291 MB bundle consumes a large share of both, and
   LFS traffic goes to `github.com` — the same endpoint that currently resets
   the connection from this network.
4. **Redistribution and licensing.** R, Rtools and MSYS2 are GPL-family; the
   109 packages carry their own licenses. Vendoring binaries into a repository
   makes the repository a redistributor and requires shipping all of that
   license text. Downloading at build time avoids the question entirely.
5. **It goes stale immediately.** A committed installer is obsolete the moment
   R or Bioconductor releases. A pinned recipe plus hashes stays correct.

## How to pre-position it anyway

If the goal is a literal self-contained directory that can be copied by USB to
an air-gapped machine, the bundle already gives you that — just point `dest` at
a location that is not the Git repository:

```powershell
Rscript 03_dependence/offline-bundle/fetch_offline_bundle.R D:\nanoamp-offline
```

Then the repository stays small and the removable payload is explicit. If you
really do want it inside the repository, add an exception to `.gitignore`
(knowing items 1-4 above still apply and the push will likely be rejected):

```gitignore
!dist/
```

For hosting rather than USB, publish `dist/` as GitHub **release assets**
instead of commits — releases are designed for large binaries, are not counted
against repository size, and keep `git clone` fast. Note that uploading them
requires the same push access that is currently blocked (see work report 6).

## Implementation notes

Two R behaviours cost real time to find and are worth recording:

* **`contriburl=` and `repos=` are not interchangeable for a local repository
  root.** `repos="file:///<root>"` resolves
  `<root>/bin/windows/contrib/<rver>/PACKAGES`; `contriburl="file:///<root>"`
  looks for `<root>/PACKAGES`. Use `repos=` with a repository root.
* **Stale index files silently hide packages.** `write_PACKAGES(addFiles=TRUE)`
  also writes `PACKAGES.gz` / `PACKAGES.rds`, and a leftover index in a parent
  directory makes `available.packages()` report fewer packages than exist on
  disk (observed: 90 reported versus 109 present). The script deletes stale
  indexes in both the leaf and the root directory, keeps only the plain
  `PACKAGES`, and asserts that the index exposes every `.zip`.
