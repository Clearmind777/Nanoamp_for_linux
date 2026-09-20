#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Install the MSYS2 / MinGW-w64 build toolchain needed to compile
    minimap2.exe from source on Windows.

.DESCRIPTION
    Fully reproducible, unattended, non-admin, and deliberately free of both
    conda and WSL:

      1. downloads the MSYS2 portable base tarball (pinned version + SHA256),
      2. extracts it with the repository's own 7-Zip if available,
      3. points pacman at a fast mirror,
      4. installs only the packages needed to build minimap2.

    The toolchain root is a machine-level tool directory, NOT part of this
    repository: a full toolchain is ~1.5 GB and must never be committed.
    This repository commits the *recipe* (this script) plus the built
    minimap2.exe under 03_dependence/windows-x86_64/bin/.

.PARAMETER ToolRoot
    Where to install the toolchain. Default: D:\tools

.PARAMETER Mirror
    MSYS2 mirror base URL. Default: TUNA (fast from CN networks).

.EXAMPLE
    pwsh -File 03_dependence/windows-x86_64/install_msys2_toolchain.ps1
    pwsh -File 03_dependence/windows-x86_64/install_msys2_toolchain.ps1 -ToolRoot C:\tools
#>
[CmdletBinding()]
param(
  [string]$ToolRoot = 'D:\tools',
  [string]$Mirror = 'https://mirrors.tuna.tsinghua.edu.cn/msys2',
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- pinned release ---------------------------------------------------------
$MsysVersion = '20250830'
$TarballName = "msys2-base-x86_64-$MsysVersion.tar.zst"
$TarballSha256 = 'A6C00B86CA0CD7FFFC8A0A35142F7B17EBAADC419F449410CF1AEC44FA92EC57'
$TarballUrl = "$Mirror/distrib/x86_64/$TarballName"

$MsysRoot = Join-Path $ToolRoot 'msys2'
$DownloadDir = Join-Path $ToolRoot 'downloads'
$Tarball = Join-Path $DownloadDir $TarballName

$PacmanPackages = @(
  'base-devel',
  'mingw-w64-x86_64-toolchain',
  'mingw-w64-x86_64-zlib',
  'mingw-w64-x86_64-cmake',
  'mingw-w64-x86_64-ninja'
)

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

function Get-SevenZip {
  foreach ($c in @('7z.exe', '7za.exe')) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
  }
  foreach ($p in @(
      "$env:USERPROFILE\scoop\apps\7zip\current\7z.exe",
      "$env:ProgramFiles\7-Zip\7z.exe",
      "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
    if (Test-Path $p) { return $p }
  }
  throw "7-Zip not found. Install it (scoop install 7zip) or add 7z.exe to PATH."
}

# --- 0. preconditions -------------------------------------------------------
Write-Step "Checking preconditions"
if ($PSVersionTable.PSVersion.Major -lt 5) { throw "PowerShell 5+ required." }
$sevenZip = Get-SevenZip
Write-Ok "7-Zip        : $sevenZip"
Write-Ok "toolchain dir: $MsysRoot"
if (Test-Path $MsysRoot) {
  $existing = Join-Path $MsysRoot 'usr\bin\pacman.exe'
  if ((Test-Path $existing) -and -not $Force) {
    Write-Warn2 "MSYS2 already present; reusing it. Pass -Force to reinstall."
  }
}

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

# --- 1. download ------------------------------------------------------------
if (-not (Test-Path $Tarball)) {
  Write-Step "Downloading $TarballName"
  # --ssl-no-revoke: this network cannot reach the certificate revocation
  # responder, which otherwise aborts the download (CRYPT_E_REVOCATION_OFFLINE).
  & curl.exe -L --fail --ssl-no-revoke --retry 5 --retry-all-errors `
    --max-time 3600 --progress-bar -o $Tarball $TarballUrl
  if ($LASTEXITCODE -ne 0) { throw "download failed: $TarballUrl" }
} else {
  Write-Step "Reusing cached $TarballName"
}

$hash = (Get-FileHash $Tarball -Algorithm SHA256).Hash
if ($hash -ne $TarballSha256) {
  throw "SHA256 mismatch for $TarballName`n  expected $TarballSha256`n  actual   $hash"
}
Write-Ok "SHA256 verified"

# --- 2. extract -------------------------------------------------------------
if ($Force -or -not (Test-Path (Join-Path $MsysRoot 'usr\bin\pacman.exe'))) {
  Write-Step "Extracting MSYS2 base"
  if (Test-Path $MsysRoot) { Remove-Item $MsysRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $MsysRoot | Out-Null

  & $sevenZip e $Tarball "-o$MsysRoot" -y | Out-Null
  $inner = Join-Path $MsysRoot ($TarballName -replace '\.tar\.zst$', '.tar')
  if (-not (Test-Path $inner)) { throw "expected inner tarball not found: $inner" }
  & $sevenZip x $inner "-o$MsysRoot" -y | Out-Null
  Remove-Item $inner -Force

  # the tarball unpacks into msys64/ - flatten it
  $nested = Join-Path $MsysRoot 'msys64'
  if (Test-Path (Join-Path $nested 'usr')) {
    Get-ChildItem $nested -Force | Move-Item -Destination $MsysRoot -Force
    Remove-Item $nested -Recurse -Force
  }
  Write-Ok "extracted to $MsysRoot"
}

# --- 3. point pacman at the mirror -----------------------------------------
Write-Step "Configuring pacman mirror"
$mingwList = Join-Path $MsysRoot 'etc\pacman.d\mirrorlist.mingw'
$msysList = Join-Path $MsysRoot 'etc\pacman.d\mirrorlist.msys'
if (Test-Path $mingwList) {
  @(
    '# nanoamp: pinned mirror for reproducible builds',
    "Server = $Mirror/mingw/`$repo/"
  ) | Set-Content -Path $mingwList -Encoding ASCII
}
if (Test-Path $msysList) {
  @(
    '# nanoamp: pinned mirror for reproducible builds',
    "Server = $Mirror/msys/`$arch/"
  ) | Set-Content -Path $msysList -Encoding ASCII
}
Write-Ok "$Mirror"

# --- 4. install packages ----------------------------------------------------
$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
if (-not (Test-Path $bash)) { throw "bash not found at $bash" }

Write-Step "Initializing pacman keyring"
& $bash -lc 'pacman-key --init >/dev/null 2>&1; pacman-key --populate msys2 >/dev/null 2>&1; pacman -Sy --noconfirm >/dev/null 2>&1; echo keyring-ok'

Write-Step "Installing build packages"
& $bash -lc "pacman -S --noconfirm --needed $($PacmanPackages -join ' ')"

# --- 5. verify --------------------------------------------------------------
Write-Step "Verifying toolchain"
& $bash -lc 'export PATH=/mingw64/bin:$PATH; gcc --version | head -1; make --version | head -1; echo "zlib.h: $(ls /mingw64/include/zlib.h)"; echo "libz.a: $(ls /mingw64/lib/libz.a)"'

Write-Host ""
Write-Ok "Toolchain ready at $MsysRoot"
Write-Host ""
Write-Host "Next: build minimap2 with" -ForegroundColor Cyan
Write-Host "  bash 03_dependence/windows-x86_64/build_minimap2.sh"
Write-Host ""
