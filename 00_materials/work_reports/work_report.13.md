# 工作报告 13 — README 补齐、代码审查修复、仓库结构规整与 v0.1.0 发布

**日期**：2026-09-25
**平台**：macOS arm64（Darwin），R 4.5.3，Biostrings 2.78.0，DECIPHER 3.6.0
**起始提交**：`7422af9`（报告 12 之后）
**对应任务**（用户原文）
1. 看看哪些 README.md / README-CN.md 是还没更新的
2. 再审查下代码有没有什么漏洞 / bug
3. 优化规整下仓库的文件结构，清除冗余 / 无用的文件 / 目录
4. 远程仓库中优先对外展示 README-CN.md
5. 在 release/ 中组织并压缩第一个 release，并发布

---

## 0. 结论摘要

| 任务 | 结果 |
|------|------|
| ① README 补齐 | 找到 3 处「完全没提功能注释」的过时 README 并补齐；根 README 加双语切换 |
| ② 代码审查 | 修掉 3 个静默产生错误结论的真实缺陷（负链坐标、退化 CDS、越界操作） |
| ③ 结构规整 | 删除 1 个失效的重复安装脚本；归档 39 个过时运行结果；统一 `.gitignore` |
| ④ 优先展示中文 | 根 `README.md` 改为中文（GitHub 默认展示文件），英文移到 `README-EN.md`，两者互加切换链接 |
| ⑤ 发布 | `release/` 就绪（3 个产物 + 校验和 + manifest + 发布说明 + 发布脚本），`R CMD check` Status: OK，功能测试 168/168 |

另外：验证过程中发现 **`release/` 归档管线自身的 2 个 bug**（见 §3），均已修复并加了守卫。

---

## 1. README 排查

逐个检查仓库内所有 README，判断是否反映当前代码：

| 文件 | 原状 | 处理 |
|------|------|------|
| `README.md`（根） | 中文，已有功能注释章节 | **加** `**中文** \| [English](README-EN.md)` 切换行 |
| `README-EN.md`（根） | 英文，已有功能注释章节 | **加** 反向切换行 |
| `02_code/README.md` | **0 处**提到 annotation / 功能注释 | 新增 “Functional annotation” 整节：两条路线、4 个新参数、输出文件、故障排查 |
| `02_code/README-CN.md` | **0 处**提到 annotation | 同上（中文） |
| `02_code/cli/README.md` | 缺 `--annotate` 系列参数 | 补参数表与示例 |
| `02_code/shared/docs/output_schema.md` | 无注释输出契约 | 补 `annotation.tsv`、`variants_annotation.tsv`、QC 指标、manifest 段、负链说明 |
| `04_results/README.md` | 无注释产物示例 | 补目录说明与归档约定 |
| `05_builds/README.md` | 无 release 说明 | 补与 `release/` 的分工 |
| `03_dependence/README.md` / `README-CN.md` | 已含 4 平台 minimap2 | 无需改动（已核对） |
| `01_data/README.md` | 已含 `manifest.tsv` 映射说明 | 无需改动（已核对） |
| `00_materials/README.md` | 报告索引 | **补** 报告 11–13 索引 |

**判据**：不只看「文件日期」，而是逐个 `grep` 本轮新增功能的对外名词
（`annotation`、`--annotate`、`consequence`、`Ensembl`、`移码`、`missense` 等）。
`02_code/README*.md` 是重灾区——它们把 CLI 用法和包 API 写得很细，却整节漏掉注释功能。

`02_code/README.md` 保持英文是**有意为之**：它作为 R 包 README 会进入构建产物
（`README-CN.md` 同理），是包面向 R 生态的入口，英文更通用。仓库对外展示由根
`README.md`（中文）负责，与任务 ④ 不冲突。

## 2. 代码审查

### 2.1 修掉的真实缺陷

这 3 个问题的共同危险特征是**不报错、不崩溃，只是安静地给出错误结论**——
比崩溃危险得多。

#### (a) 负链转录本上的变异被静默丢弃

```r
# 修复前（02_code/R/annotate.R, annotation_cds_frame）
gp <= start && gp >= end          # 负链时 start > end，恒为假
```

负链转录本的 CDS 区间满足 `start > end`，因此 `gp <= start && gp >= end` 永远不成立，
该转录本上**所有**变异都被判为「不在 CDS 内」，一个移码/无义突变都报不出来，
而 `annotation.tsv` 依然正常输出、依然写着 `consequence = 同义`。

修复后改为与链无关的区间包含判断，再叠加转录本方向偏移：

```r
gp >= min(start, end) && gp <= max(start, end)
```

合成镜像测试（正链序列取反向互补 + 负链坐标）验证：

| 场景 | 修复前命中 | 修复后命中 |
|------|-----------|-----------|
| 单区块负链，变异 1 | 0 | 1 |
| 单区块负链，变异 2 | 0 | 15 |
| 单区块负链，变异 3 | 0 | 18 |
| 多区块负链，变异 1 | 0 | 1 |
| 多区块负链，变异 2 | 0 | 36 |

#### (b) 退化 CDS 被判为「同义」

CDS 序列为空、或长度不是 3 的倍数时，旧代码照样翻译、照样比较，
返回 `cds_ok = TRUE` 且 `consequence = synonymous`。现在这两种情况直接拒绝并写明原因。

#### (c) 越界变异被静默追加/截断

`.annotation_apply_ops` 在变异位置超出序列范围时，旧实现会静默地把序列截断
或把新碱基追加到末尾，从而在**错误的坐标上**算出一个看起来正常的氨基酸变化。
现在对「越界位置」与「删除跨过序列末端」明确报错。

### 2.2 查出但判定为非缺陷的点

- `overlap/id?feature=exon` 返回的是**位点范围**的外显子，不是该转录本自己的外显子。
  因此 UTR 目前只能判到「落在任一外显子内」。已记入限制，未强行修（需要另一套接口）。
- `protein_change` 是 HGVS **风格**而非经 HGVS 认证的实现。已记入限制。
- 参考匹配率低于 0.9 时拒绝定位：这是**设计选择**（宁可拒绝也不给错坐标），非缺陷。
  F12 扩增子匹配率 0.39，被正确拒绝并列出了备选位点。

## 3. 归档管线自身的 2 个 bug（本轮新发现）

构建第一个 release 时，产物尺寸异常暴露了两个问题。

### (a) `git archive` 的格式参数写错 → `.tar.gz` 其实是未压缩的纯 tar

```bash
git archive --format=tar --prefix="$PREFIX/" "$REF" -o "$TMP/$PREFIX-src.tar.gz"
#                    ^^^ 生成 POSIX tar，扩展名却是 .tar.gz
```

`file` 的判定结果：

```
nanoamp-0.1.0-src.tar.gz: POSIX tar archive      # 应为 "gzip compressed data"
```

后果：体积从约 67 MB 涨到约 87 MB，且文件头与扩展名不符（部分工具会拒绝）。
修复：`--format=tar.gz`，并加 `gzip -t` 守卫——**如果哪天又退化成纯 tar，脚本会直接失败**。

### (b) `zip` 用了默认的 store 模式且参数顺序错误

两个独立问题：

1. 参数顺序：`zip -q -r out.zip . -i dir` 中的 `-i` 被 Info-ZIP 当成文件名，
   报 `zip error: Nothing to do!`。
2. 未指定压缩级别时走 store（仅打包不压缩）。

修复为 `zip -q -9 -r -X "$PREFIX-src.zip" "$PREFIX"`（最高压缩、不写多余元数据），
并加 `unzip -tq` 校验。

### (c) 预防：`git archive` 不读 `.gitignore`，只认 `export-ignore`

`release/` 在 `.gitignore` 中，但 `git archive` 用的是 `.gitattributes`。若不处理，
**每次发新版都会把上一版的 tarball 打包进新版**，归档体积逐版膨胀。
已在 `.gitattributes` 增加：

```
release/        export-ignore
```

并额外加了守卫：`tar xzf` 会拦住格式错误，脚本对 `release/` 是否混入不做静默容忍。

**教训**：归档脚本必须在产出后**复核自己的产物**（类型、内容、体积），
否则「发布了一个坏包」这件事本身不会有任何提示。

## 4. 仓库结构规整

| 动作 | 对象 | 理由 |
|------|------|------|
| 删除 | `02_code/cli/install_cli.sh` | 与 `02_code/inst/scripts/install_cli.sh` 重复；前者已失效 |
| 保留 | `02_code/cli/nanoamp.R`、`inst/scripts/install_cli.sh` | 作用不同（仓库内启动器 vs 安装后的启动器） |
| 归档 | `04_results/r/` 下 39 个过时运行目录 → `_archive/r/` | 保留可追溯性，但不再干扰当前结果 |
| 保留 | `test_run_3`、`test_run_bundled`、`test_run_macos_arm64`、`round2` | 分别对应三个平台的验证与 round2 基线 |
| 新增 | `release/` | 发布产物与说明 |
| 更新 | `.gitignore`：`release/*.tar.gz`、`release/*.zip`、`release/archive/` | 大体积二进制走 GitHub Release 渠道，不进 git |
| 更新 | `.gitattributes`：`release/ export-ignore` | 见 §3(c) |
| 核对 | 无 debug/临时文件被跟踪；`.DS_Store` 已在 ignore 中 | 检查通过 |

`release/` 中**入 git** 的只有 5 个文本文件（`README.md`、`RELEASE_NOTES.md`、
`manifest.tsv`、`SHA256SUMS`、`publish_github_release.sh`），
3 个大体积归档（约 137 MB）走 GitHub Release 分发。

## 5. 优先展示 README-CN.md

用户希望远程仓库页面优先显示中文说明。GitHub 的规则是
**仓库根目录的 `README.md` 自动成为默认展示文件**，因此做法是让根 `README.md` 的内容为中文：

```
README.md      -> 中文（GitHub 仓库首页默认展示）
README-EN.md   -> English
```

两份都在 H1 下方加了互跳链接（`**中文** | [English](README-EN.md)`），
使 GitHub 上可以一键切换。

同时确认：`README-CN.md` / `README-EN.md` 这类**非默认文件名不会被 GitHub 自动渲染**，
所以「把中文放在 `README-CN.md` 里」反而达不到目的。任务 ④ 的正确解法就是当前做法。

## 6. 第一个 release：v0.1.0

### 6.1 产物

命名与分工：

| 文件 | 体积 | 用途 |
|------|------|------|
| `nanoamp-0.1.0-src.tar.gz` | 69,961,887 B | 完整源码树（含 `01_data/test_data`），可复现全部结果 |
| `nanoamp-0.1.0-src.zip` | 69,983,098 B | 同上，ZIP 便于图形界面解压 |
| `nanoamp-0.1.0-R-package.tar.gz` | 72,232 B | 标准 R 包源码，`R CMD INSTALL` 用 |
| `SHA256SUMS` | — | 三个产物的 SHA-256 |
| `manifest.tsv` | — | 版本 / 提交 / 构建时间 / 大小 / 校验和 / 工具链 / 数据源 |
| `RELEASE_NOTES.md` | — | 发布说明（同时作为 GitHub Release 正文） |
| `publish_github_release.sh` | — | 一键发布脚本（`gh` 优先，回退 REST API） |

### 6.2 为什么必须包含 `01_data/test_data`

功能测试的 168/168 与模式 A/B/C 的定量结果（top-1 比例 0.6750 / 0.7584 / 0.1231）
**只在这份数据上可复现**。`01_data/test_data` 共 409 个文件约 80 MB，已被 git 跟踪，
因此 `git archive` 天然含入。刻意不裁剪。

### 6.3 可复现的构建

新增 `02_code/scripts/mk-release.sh`，设计要点：

- 归档由 **`git archive`** 生成 ⇒ 产物严格等于某个 commit，不受工作区未提交改动影响；
- R 包在**解压出的纯净树**上 `R CMD build` + `R CMD check` ⇒ 不会误用工作区的脏文件；
- `manifest.tsv` 由脚本**重新生成** ⇒ 尺寸/校验和不会与产物脱节；
- 兼容 macOS 自带的 bash 3.2（不使用 `mapfile` 等 bash 4 特性）。

在纯净产物上执行 `R CMD check --no-manual --no-build-vignettes`：

```
Status: OK
```

`Makefile` 增加三个目标：

```make
make release          # 从当前 tag（无 tag 则 HEAD）重建 release/ 全部产物
make release-check    # 只校验校验和与凭据，不发布
make release-publish  # 推送到 GitHub Release
```

### 6.4 发布脚本

`release/publish_github_release.sh` 的行为：

- 从 `manifest.tsv` 读 tag，从 `origin` 推断 `owner/repo`；
- 先校验 `SHA256SUMS`，缺文件即失败；
- 若无 `gh` 且无 token，**打印三条可选路径后以非零状态退出**（不静默跳过发布）；
- 有凭据时：Release 已存在则覆盖同名附件（**幂等**，可反复执行）；
- `DRY_RUN=1` 只做校验。

本机现状：**没有 GitHub API 凭据**（`GH_TOKEN`/`GITHUB_TOKEN` 未设置，`gh` 未安装，
keychain 无 https 凭据）。远端是 SSH（`git@github.com:Clearmind777/Nanoamp_for_linux.git`），
SSH 认证正常，因此 **`git push` 可用而 GitHub Release 的创建需要额外凭据**。
已把确切命令交给用户（见 §8）。

## 7. 验证结果

| 项目 | 结果 |
|------|------|
| `make test`（testthat） | 通过 |
| `R CMD check --no-manual`（工作区） | Status: OK |
| `R CMD check --no-manual`（**纯净归档树**） | **Status: OK** |
| 功能测试 | **168/168 ok**（3 模式 × 56 组，0 error） |
| 归档类型守卫 | `file` 判定为 gzip compressed data；`gzip -t` 通过 |
| zip 完整性 | `unzip -tq` 通过 |
| 校验和 | `shasum -a 256 -c SHA256SUMS` 三个文件全 OK |
| 发布脚本 | `bash -n` 通过；`DRY_RUN=1` 通过；无凭据路径正确 `exit 1` |

功能测试基准（`04_results/r/test_run_3/functional_test.log`）：

```
 mode n_runs n_ok n_error mean_top1_proportion mean_overlap_rate
    A     56   56       0               0.6750            0.9807
    B     56   56       0               0.7584            0.5048
    C     56   56       0               0.1231            0.0000
```

## 8. 交付给用户的发布操作

已完成（本轮）：提交 `5eacf9b`（release 产物与说明）+ `0d7ab34`（发布脚本修正），
annotated tag `v0.1.0`，`git push origin main` 与 `git push origin v0.1.0` 均成功。
远端核验：默认分支 `main`，根 README 已是中文（`**中文** | [English](README-EN.md)`），
tag `v0.1.0^{}` = `5eacf9b`，且远端当前**没有任何 Release**。

**剩余一步**：本机没有 GitHub API 凭据，创建 Release 需要用户授权。

```bash
# 1) gh 已装好（2.101.0，/opt/homebrew/bin/gh），只差一次交互式登录：
gh auth login            # 选 GitHub.com -> HTTPS -> Login with a web browser
gh auth status           # 确认已登录

# 2) 一键发布（幂等；Release 已存在时覆盖同名附件）
./release/publish_github_release.sh      # 或 make release-publish

# 3) 若不想用 gh，也可用 token：
GH_TOKEN=<token> ./release/publish_github_release.sh
```

若两者都不做，可在浏览器打开
`https://github.com/Clearmind777/Nanoamp_for_linux/releases/new?tag=v0.1.0`，
正文粘贴 `release/RELEASE_NOTES.md`，附件拖入 `release/` 下 3 个产物
（`nanoamp-0.1.0-src.tar.gz` 67 MB、`nanoamp-0.1.0-src.zip` 67 MB、
`nanoamp-0.1.0-R-package.tar.gz` 71 KB）。

发布脚本的健壮性已单独验证：`bash -n` 通过、`DRY_RUN=1` 通过、无凭据时正确 `exit 1`
并打印三条可选路径、会自动把 `/opt/homebrew/bin` 补进 `PATH`（非登录 shell 常见缺失）。

## 9. 遗留问题

- **GitHub Release 尚未创建**：缺少 API 凭据，需要用户 `gh auth login` 或提供 token
  （代码、tag、归档、校验和、发布说明均已就绪，只差最后一步上传）。
- **`All` 模式较慢**：受 Ensembl 节流（1.1 s/请求）限制，建议先用 `--list-transcripts`。
- **负链仅有合成镜像测试**：`01_data` 中所有目标都定位在正链，缺少真实负链数据集。
- **TUI 未提供注释界面**：见 `TUI_plan.1.md` 的转录本多选设计。
- **转录本级 UTR 精度**：受 `overlap/id?feature=exon` 的位点级语义限制。
