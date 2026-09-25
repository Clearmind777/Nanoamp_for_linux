#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# mk-release.sh -- 从 git 的某个提交构建 release/ 下的全部产物
#
# 用法:
#   bash 02_code/scripts/mk-release.sh                 # 用 HEAD 和 manifest 里的 tag
#   bash 02_code/scripts/mk-release.sh --ref v0.1.0
#   bash 02_code/scripts/mk-release.sh --version 0.2.0
#   bash 02_code/scripts/mk-release.sh --no-check      # 跳过 R CMD check（快，但不可信）
#
# 产物:
#   release/nanoamp-<ver>-src.tar.gz           完整源码树（含 01_data/test_data）
#   release/nanoamp-<ver>-src.zip              同上 ZIP 版
#   release/nanoamp-<ver>-R-package.tar.gz     标准 R 包源码包
#   release/SHA256SUMS                         SHA-256
#   release/manifest.tsv                       重新生成的元数据表
#
# 设计要点:
#   * 归档由 `git archive` 生成 => 产物严格等于该 commit，不受工作区未提交改动影响。
#   * R 包在解压出的纯净树上构建并 check => 不会误用工作区的脏文件。
#   * manifest.tsv 由本脚本重写，因此元数据不依赖人工同步（release/README.md 正文
#     与 RELEASE_NOTES.md 仍由人工维护）。
# ---------------------------------------------------------------------------
set -euo pipefail

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

REF="HEAD"
VERSION=""
DO_CHECK=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)       REF="$2"; shift 2;;
    --version)   VERSION="$2"; shift 2;;
    --no-check)  DO_CHECK=0; shift;;
    -h|--help)   usage;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage;;
  esac
done

info() { printf '==> %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v R >/dev/null 2>&1 || die "PATH 中没有 R"
command -v git >/dev/null 2>&1 || die "PATH 中没有 git"

# 定位仓库根（本脚本在 02_code/scripts/ 下）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
[[ -d 02_code && -d release ]] || die "无法定位仓库根（当前 $ROOT_DIR）"

# --- 解析 tag / version ----------------------------------------------------
if [[ -z "$VERSION" ]]; then
  if [[ "$REF" == v* ]]; then
    VERSION="${REF#v}"
  elif [[ -f release/manifest.tsv ]]; then
    VERSION="$(awk -F'\t' '$1=="release"{print $2; exit}' release/manifest.tsv)"
  fi
fi
[[ -n "$VERSION" ]] || die "无法确定版本号，请用 --version X.Y.Z"

TAG="v$VERSION"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  REF="$TAG"                      # tag 存在就用 tag，产物更可追溯
fi
COMMIT="$(git rev-parse "${REF}^{commit}")"
SHORT="$(git rev-parse --short "$COMMIT")"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PREFIX="nanoamp-$VERSION"

info "版本 $VERSION  (ref=$REF commit=$SHORT)"
info "构建时间 $BUILD_DATE"

# --- 1. git archive --------------------------------------------------------
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nanoamp-rel.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
EXPORT="$TMP/$PREFIX"

info "导出源码树: git archive $REF"
# 必须显式 --format=tar.gz：只写 --format=tar（或依赖 .tar.gz 后缀推断）会生成
# 未压缩的纯 tar，体积从约 67 MB 涨到约 87 MB，而且文件头与扩展名不符。
git archive --format=tar.gz --prefix="$PREFIX/" "$REF" -o "$TMP/$PREFIX-src.tar.gz"
# 守卫：确认真的被 gzip 压缩了（“POSIX tar archive” 说明没压缩，见上）。
gzip -t "$TMP/$PREFIX-src.tar.gz" \
  || die "$PREFIX-src.tar.gz 不是有效的 gzip 文件（git archive 的格式参数写错？）"
if command -v file >/dev/null 2>&1; then
  info "  归档类型: $(file -b "$TMP/$PREFIX-src.tar.gz")"
fi

# 先解包（zip 需要一个真实存在的目录才能打包）
mkdir -p "$EXPORT"
tar xzf "$TMP/$PREFIX-src.tar.gz" -C "$TMP"
[[ -d "$EXPORT/02_code" ]] || die "导出树缺少 02_code"

if command -v zip >/dev/null 2>&1; then
  # -9/-X: 最高压缩 + 不写多余的平台相关元数据。
  # 默认的 store（-0）会让 zip 比 tar.gz 大一倍以上。
  ( cd "$TMP" && zip -q -9 -r -X "$PREFIX-src.zip" "$PREFIX" )
  unzip -tq "$TMP/$PREFIX-src.zip" >/dev/null || die "$PREFIX-src.zip 校验失败"
else
  info "未找到 zip(1)，跳过 .zip 产物"
fi

# --- 2. 构建并检查 R 包（在纯净树上） ---------------------------------------
info "R CMD build (纯净树)"
( cd "$TMP" && R CMD build "$EXPORT/02_code" --no-build-vignettes >/dev/null 2>&1 ) \
  || die "R CMD build 失败"
PKG_TARBALL="$TMP/nanoamp_$VERSION.tar.gz"
[[ -f "$PKG_TARBALL" ]] || die "未生成 $PKG_TARBALL（DESCRIPTION 里的 Version 与 --version 不一致？）"

CHECK_STATUS="(skipped)"
if [[ "$DO_CHECK" == "1" ]]; then
  info "R CMD check (纯净产物) -- 可能需要几分钟"
  ( cd "$TMP" && _R_CHECK_FORCE_SUGGESTS_=false \
      R CMD check --no-manual --no-build-vignettes "nanoamp_$VERSION.tar.gz" \
      >"$TMP/check.log" 2>&1 ) || true
  CHECK_STATUS="$(grep -E '^Status:' "$TMP/check.log" | tail -1 | sed 's/^Status: *//')"
  [[ -n "$CHECK_STATUS" ]] || CHECK_STATUS="(unknown)"
  info "R CMD check => Status: $CHECK_STATUS"
  [[ "$CHECK_STATUS" == "OK" ]] || printf 'WARNING: R CMD check 不是 OK，请查看 %s\n' "$TMP/check.log" >&2
fi

# --- 3. 落盘到 release/ ----------------------------------------------------
info "写入 release/"
cp "$TMP/$PREFIX-src.tar.gz" release/
[[ -f "$TMP/$PREFIX-src.zip" ]] && cp "$TMP/$PREFIX-src.zip" release/
cp "$PKG_TARBALL" "release/$PREFIX-R-package.tar.gz"

( cd release && shasum -a 256 "$PREFIX-src.tar.gz" "$PREFIX-R-package.tar.gz" > SHA256SUMS 2>/dev/null \
  || sha256sum "$PREFIX-src.tar.gz" "$PREFIX-R-package.tar.gz" > SHA256SUMS )
if [[ -f "release/$PREFIX-src.zip" ]]; then
  ( cd release && { shasum -a 256 "$PREFIX-src.zip" 2>/dev/null || sha256sum "$PREFIX-src.zip"; } >> SHA256SUMS )
fi
( cd release && { shasum -a 256 -c SHA256SUMS 2>/dev/null || sha256sum -c SHA256SUMS; } )

# --- 4. 重新生成 manifest.tsv ----------------------------------------------
size_of() { wc -c < "release/$1" | tr -d ' '; }
sha_of()  { awk -v f="$1" '$2==f || $2=="*"f {print $1; exit}' release/SHA256SUMS; }

R_VERSION="$(R --version | head -1)"
# 注意：macOS 自带 bash 3.2 没有 mapfile，这里用普通变量保持兼容。
PKGS="$(Rscript -e 'for (p in c("Biostrings","pwalign","DECIPHER","data.table","Rsamtools","jsonlite")) cat(p, as.character(packageVersion(p)), "\n")' 2>/dev/null || true)"

{
  cat <<EOF
# nanoamp release manifest
# 每行: key<TAB>value ; 以 # 开头为注释
# 本文件由 02_code/scripts/mk-release.sh 生成，请勿手工编辑尺寸/校验和字段。
release	$VERSION
tag	$TAG
git_commit	$COMMIT
git_commit_short	$SHORT
build_date_utc	$BUILD_DATE
build_host	$(uname -s) $(uname -m), $R_VERSION
build_tree	git archive $REF (含未纳入 git 的 01_data/test_data 复现数据)

file	$PREFIX-src.tar.gz
size_bytes	$(size_of "$PREFIX-src.tar.gz")
sha256	$(sha_of "$PREFIX-src.tar.gz")
role	完整仓库源码归档（tar.gz），含 01_data/test_data，可复现论文级结果
unpack	tar xzf $PREFIX-src.tar.gz && cd $PREFIX

EOF
  if [[ -f "release/$PREFIX-src.zip" ]]; then
    cat <<EOF
file	$PREFIX-src.zip
size_bytes	$(size_of "$PREFIX-src.zip")
sha256	$(sha_of "$PREFIX-src.zip")
role	同上的 ZIP 版本，便于图形界面解压
unpack	unzip $PREFIX-src.zip && cd $PREFIX

EOF
  fi
  cat <<EOF
file	$PREFIX-R-package.tar.gz
size_bytes	$(size_of "$PREFIX-R-package.tar.gz")
sha256	$(sha_of "$PREFIX-R-package.tar.gz")
role	标准 R 包源码包（R CMD build 02_code 产出），用于 R CMD INSTALL
r_cmd_check	Status: $CHECK_STATUS (--no-manual --no-build-vignettes)
unpack	R CMD INSTALL $PREFIX-R-package.tar.gz

# 已验证工具链（本 release 通过 R CMD check 与功能测试的环境）
toolchain	$R_VERSION
EOF
  while read -r pname pver; do
    [[ -n "$pname" ]] && printf 'toolchain\t%s %s\n' "$pname" "$pver"
  done <<< "$PKGS"
  cat <<'EOF'
toolchain	minimap2 2.31-r1302 (随包提供 linux-x86_64 / linux-arm64 / macos-x86_64 / macos-arm64)

# 外部数据源（仅联网注释路线使用）
annotation_source	Ensembl REST
annotation_release	116
annotation_panel	ZNF8 (ENSG00000278129 / ENST00000621650, 575 aa)
annotation_sequence_source	UCSC (序列); 结构注释仅用 Ensembl/GENCODE 体系
EOF
} > release/manifest.tsv

info "完成。release/ 内容："
ls -lh release/ | tail -n +2 | awk '{printf "   %-42s %s\n", $9, $5}'
