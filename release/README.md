# release/ — 发布产物目录

本目录存放对外发布用的归档与元数据。**大体积产物不入 git**（见 `../.gitignore`），
每次发布时在本地重新构建并上传到 GitHub Release。

## 当前版本：v0.1.0

| 文件 | 大小 | 入 git | 说明 |
|------|------|--------|------|
| `nanoamp-0.1.0-src.tar.gz` | 69,961,887 B | 否 | 完整仓库源码归档（含 `01_data/test_data`，可复现全部结果） |
| `nanoamp-0.1.0-src.zip` | 69,983,098 B | 否 | 同上 ZIP 版 |
| `nanoamp-0.1.0-R-package.tar.gz` | 72,232 B | 否 | 标准 R 包源码，`R CMD INSTALL` 用 |
| `SHA256SUMS` | — | 是 | 上述三个产物的 SHA-256 |
| `manifest.tsv` | — | 是 | 版本 / 提交 / 构建时间 / 大小 / 校验和 / 工具链 / 数据源 |
| `RELEASE_NOTES.md` | — | 是 | 发布说明（同时作为 GitHub Release 正文） |
| `publish_github_release.sh` | — | 是 | 一键发布脚本（`gh` 优先，回退 REST API） |

> **为什么大文件不入 git**：仓库已在 `01_data/test_data`（约 80 MB）与 conda 环境上达到 2.4 GB。
> 归档文件可从 tag 完整重建，放进 git 只会让每次 clone 更慢。GitHub Release 本身就是这些
> 二进制的分发渠道。

## 重新构建本版本

**一条命令**（推荐；会导出纯净树、构建、`R CMD check`、写校验和并重写 `manifest.tsv`）：

```bash
bash 02_code/scripts/mk-release.sh --version 0.1.0     # 或 make release
```

`--ref <tag|commit>` 可指定来源；`--no-check` 跳过 `R CMD check`（快但不可信）。

脚本内部的关键点（手工复现时同样必须遵守）：

1. **归档用 `git archive` 生成**，产物严格等于某个 commit，不受工作区未提交改动影响：

   ```bash
   PREFIX=nanoamp-0.1.0
   git archive --format=tar.gz --prefix="$PREFIX/" "$REF" -o "release/$PREFIX-src.tar.gz"
   ```

   注意必须写 `--format=tar.gz`。只写 `--format=tar` 会生成**未压缩的纯 tar**
   （体积从 67 MB 涨到 87 MB，且文件头与扩展名不符）。`mk-release.sh` 内部用
   `gzip -t` 做了守卫。

2. **R 包在解压出的纯净树上构建**，避免误用工作区的脏文件：

   ```bash
   R CMD build <exported-tree>/$PREFIX/02_code --no-build-vignettes
   R CMD check --no-manual --no-build-vignettes nanoamp_0.1.0.tar.gz   # 期望 Status: OK
   ```

3. **ZIP 用 `-9 -X`**：`zip` 默认对小于阈值的条目走 store 模式，
   必须 `zip -q -9 -r -X "$PREFIX-src.zip" "$PREFIX"`，并 `unzip -tq` 校验。

4. `manifest.tsv` 由脚本**重新生成**，尺寸与校验和不会与产物脱节。

`git archive` 只收录被 git 跟踪的文件。`01_data/test_data`（409 个文件，约 80 MB）**是被跟踪的**，
因此归档中包含它。这一点很关键：功能测试的 168/168 与模式 A/B/C 的定量结果只有在这份数据上
才能复现。请勿把 `01_data/test_data` 移出 git，否则 release 归档会失去可复现性。

`release/` 自身在 `.gitattributes` 中被标为 `export-ignore`，因此不会被卷进归档。
**这一点必须保留**：`git archive` 不读 `.gitignore`，若去掉该规则，每次发新版都会把上一版的
tarball 打包进新版，归档体积逐版膨胀。

（`01_data/test_data` 中若干 `.xlsx` 是实验室原始统计表，文件名含中文。它们不参与程序运行，仅作留档。）

## 发布

```bash
./release/publish_github_release.sh               # 需要 gh auth login 或 GH_TOKEN
DRY_RUN=1 ./release/publish_github_release.sh     # 只校验，不发布
```

前置条件：`git push origin v0.1.0`（Release 必须有对应的远端 tag）。
脚本幂等：Release 已存在时只覆盖同名附件。

## 新增下一个版本

1. 确认 `02_code/DESCRIPTION` 里的 `Version:` 已是新版本号。
2. 重建产物（文件名带版本号，避免与历史产物互相覆盖）：

   ```bash
   bash 02_code/scripts/mk-release.sh --version X.Y.Z
   ```

   该脚本会一并重写 `SHA256SUMS` 与 `manifest.tsv`，**不需要手工填任何尺寸或校验和**。
3. 人工维护两份文档：
   - 把当前 `RELEASE_NOTES.md` 快照为 `RELEASE_NOTES-v0.1.0.md` 存档，再为新版本重写正文；
   - 更新本文件中的版本表格。
4. 提交 → 打 tag → 推送 → 发布：

   ```bash
   git add -A && git commit -m "release: vX.Y.Z"
   git tag -a vX.Y.Z -m "nanoamp vX.Y.Z"
   git push origin main && git push origin vX.Y.Z
   ./release/publish_github_release.sh
   ```

> 归档内容等于 `mk-release.sh --ref` 指定的那个 commit。若说明类文件在构建之后才提交，
> 归档中不含它们——这是刻意的：归档只承载代码与数据，说明由 GitHub Release 正文呈现。

版本号规则见 `../programs_dev_plan_1.md` §14。
