#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# publish_github_release.sh -- 把 release/ 中的产物发布为 GitHub Release
#
# 用法:
#   GH_TOKEN=ghp_xxx  ./release/publish_github_release.sh
#   # 或先 gh auth login，然后:
#   ./release/publish_github_release.sh
#
# 可选环境变量:
#   GH_TOKEN / GITHUB_TOKEN   有 repo 权限的 token（优先使用）
#   REPO     覆盖仓库，默认从 git remote 推断，形如 Clearmind777/Nanoamp_for_linux
#   TAG      覆盖 tag，默认读取 release/manifest.tsv 中的 tag
#   DRAFT=1  以草稿形式创建
#   PRERELEASE=1  标记为预发布
#   DRY_RUN=1  只做校验与凭据检查，不实际发布
#
# 脚本是幂等的：若 Release 已存在，则只补充/更新附件。
# 注意：脚本不会自动打 tag；请先确认 tag 已推送到远端（见文末提示）。
# ---------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$0")"                 # release/
RELEASE_DIR="$(pwd)"
ROOT_DIR="$(cd .. && pwd)"
cd "$ROOT_DIR"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

# --- 1. 读取元数据 ---------------------------------------------------------
[[ -f release/manifest.tsv ]] || die "缺少 release/manifest.tsv"
manifest_get() { awk -F'\t' -v k="$1" '$1==k {print $2; exit}' release/manifest.tsv; }

TAG="${TAG:-$(manifest_get tag)}"
VERSION="${TAG#v}"
[[ -n "$TAG" ]] || die "无法确定 tag"

REPO="${REPO:-}"
if [[ -z "$REPO" ]]; then
  url="$(git remote get-url origin 2>/dev/null || true)"
  case "$url" in
    git@github.com:*)      REPO="${url#git@github.com:}";;
    https://github.com/*)  REPO="${url#https://github.com/}";;
    ssh://git@github.com/*) REPO="${url#ssh://git@github.com/}";;
    *) die "无法从 origin 推断 REPO，请显式设置 REPO=owner/name (origin=$url)";;
  esac
  REPO="${REPO%.git}"
fi
info "仓库: $REPO    tag: $TAG    release: $VERSION"

# --- 2. 校验产物 -----------------------------------------------------------
[[ -f release/SHA256SUMS ]] || die "缺少 release/SHA256SUMS"
info "校验产物校验和"
if command -v sha256sum >/dev/null 2>&1; then
  (cd release && sha256sum -c SHA256SUMS)
else
  (cd release && shasum -a 256 -c SHA256SUMS)
fi

ASSETS=()
while IFS= read -r f; do
  [[ -f "release/$f" ]] || die "SHA256SUMS 中列出的文件不存在: release/$f"
  ASSETS+=("release/$f")
done < <(awk '{print $2}' release/SHA256SUMS | sed 's/^\*//')
ASSETS+=("release/SHA256SUMS" "release/manifest.tsv" "release/RELEASE_NOTES.md")
info "附件数量: ${#ASSETS[@]}"

NOTES_FILE="${NOTES_FILE:-release/RELEASE_NOTES.md}"
[[ -f "$NOTES_FILE" ]] || die "缺少发布说明 $NOTES_FILE"

# --- 3. 确认远端已有该 tag --------------------------------------------------
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  if ! git ls-remote --tags origin "refs/tags/$TAG" | grep -q .; then
    printf 'WARNING: 本地存在 tag %s 但远端没有。请先执行:\n  git push origin %s\n' "$TAG" "$TAG" >&2
  fi
else
  printf 'WARNING: 本地没有 tag %s。GitHub Release 需要一个已存在的 tag。\n' "$TAG" >&2
fi

# --- 4. 选择发布通道: gh CLI 优先，否则 REST API ----------------------------
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

# gh 常常装在 PATH 之外（Homebrew 的 /opt/homebrew/bin 在非登录 shell 里可能缺失），
# 所以显式补上常见位置。
for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin"; do
  [[ -x "$d/gh" ]] && case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH";; esac
done
export PATH
export GH_PROMPT_DISABLED=1     # 无人交互：gh 不要弹提示，直接失败

# gh 是否可用且已登录（失败会自动走下面的 token/报错分支）
gh_ready() {
  command -v gh >/dev/null 2>&1 || return 1
  gh auth status >/dev/null 2>&1
}

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  info "DRY_RUN: 校验通过，未发布。"
  printf '   tag        : %s\n' "$TAG"
  printf '   repo       : %s\n' "$REPO"
  printf "   附件       : %s\n" "${ASSETS[*]##*/}"
  if [[ -n "$TOKEN" ]]; then
    printf '   凭据       : 已提供 token（将走 REST API）\n'
  elif gh_ready; then
    printf '   凭据       : gh CLI 已登录\n'
  elif command -v gh >/dev/null 2>&1; then
    printf '   凭据       : gh 已安装但未登录（需要 gh auth login）\n'
  else
    printf '   凭据       : 缺失（需要 gh auth login 或 GH_TOKEN）\n'
  fi
  exit 0
fi

if [[ -z "$TOKEN" ]] && gh_ready; then
  info "使用 gh CLI 发布"
  EXTRA=()
  [[ "${DRAFT:-0}" == "1" ]] && EXTRA+=(--draft)
  [[ "${PRERELEASE:-0}" == "1" ]] && EXTRA+=(--prerelease)
  # 注意：bash 3.2 下空数组配 `set -u` 会报 unbound variable，因此统一用
  # `${EXTRA[@]+"${EXTRA[@]}"}` 这种“有元素才展开”的写法。
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    info "Release $TAG 已存在，改为上传/覆盖附件"
    gh release upload "$TAG" "${ASSETS[@]}" --repo "$REPO" --clobber
  else
    gh release create "$TAG" "${ASSETS[@]}" \
      --repo "$REPO" \
      --title "nanoamp $VERSION" \
      --notes-file "$NOTES_FILE" \
      ${EXTRA[@]+"${EXTRA[@]}"}
  fi
  info "完成: https://github.com/$REPO/releases/tag/$TAG"
  exit 0
fi

# --- 无 gh: 走 REST API ----------------------------------------------------
if [[ -z "$TOKEN" ]]; then
  cat >&2 <<EOF
ERROR: 没有可用的 GitHub 凭据。三选一：

  A) 安装并登录 gh CLI（推荐，脚本会全自动上传附件）
       brew install gh && gh auth login
       ./release/publish_github_release.sh

  B) 使用 Personal Access Token（需要 repo 权限）
       GH_TOKEN=<你的token> ./release/publish_github_release.sh

  C) 只创建 Release（不含附件），在浏览器里手动拖拽 release/ 下的 3 个产物
       GH_TOKEN=<你的token> curl -sS -X POST \\
         -H "Authorization: Bearer <你的token>" \\
         -H "Accept: application/vnd.github+json" \\
         https://api.github.com/repos/$REPO/releases \\
         -d '{"tag_name":"$TAG","name":"nanoamp $VERSION","body":"见 release/RELEASE_NOTES.md","draft":false}'

  发布页: https://github.com/$REPO/releases/new?tag=$TAG
EOF
  exit 1
fi


info "使用 GitHub REST API 发布 (token 已提供)"
API="https://api.github.com/repos/$REPO"
auth=(-H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

release_id="$(curl -sS "${auth[@]}" "$API/releases/tags/$TAG" \
  | sed -n 's/.*"id": *\([0-9]\{1,\}\).*/\1/p' | head -1 || true)"

if [[ -z "$release_id" ]]; then
  info "创建 Release $TAG"
  payload="$(VERSION="$VERSION" TAG="$TAG" NOTES="$NOTES_FILE" DRAFT="${DRAFT:-0}" PRE="${PRERELEASE:-0}" python3 - <<'PY'
import json, os
print(json.dumps({
    "tag_name": os.environ["TAG"],
    "name": "nanoamp " + os.environ["VERSION"],
    "body": open(os.environ["NOTES"], encoding="utf-8").read(),
    "draft": os.environ["DRAFT"] == "1",
    "prerelease": os.environ["PRE"] == "1",
}))
PY
)"
  resp="$(curl -sS -X POST "${auth[@]}" "$API/releases" -d "$payload")"
  release_id="$(printf '%s' "$resp" | sed -n 's/.*"id": *\([0-9]\{1,\}\).*/\1/p' | head -1)"
  [[ -n "$release_id" ]] || die "创建 Release 失败: $resp"
else
  info "Release $TAG 已存在 (id=$release_id)，继续上传附件"
fi

upload_base="https://uploads.github.com/repos/$REPO/releases/$release_id/assets"
for f in "${ASSETS[@]}"; do
  name="$(basename "$f")"
  # 同名附件先删掉，保证可重复执行
  old="$(curl -sS "${auth[@]}" "$API/releases/$release_id/assets" \
        | python3 -c 'import json,sys;print("\n".join(str(a["id"]) for a in json.load(sys.stdin) if a["name"]==sys.argv[1]))' "$name" 2>/dev/null || true)"
  for id in $old; do
    curl -sS -X DELETE "${auth[@]}" "$API/releases/assets/$id" >/dev/null || true
  done
  info "上传 $name ($(wc -c <"$f" | tr -d ' ') bytes)"
  curl -sS -X POST "${auth[@]}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"$f" \
    "$upload_base?name=$name" >/dev/null
done

info "完成: https://github.com/$REPO/releases/tag/$TAG"
