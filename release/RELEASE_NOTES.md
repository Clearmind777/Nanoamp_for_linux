# nanoamp v0.1.0 发布说明

**发布日期**：2026-09-25
**提交**：`7422af9` (`7422af9223f05e060bbb6cbf0fe367d8126b0e3a`)
**许可**：见仓库 `LICENSE`
**平台**：Linux / macOS（x86_64 与 arm64），纯命令行（CLI）

---

## 1. 这是什么

`nanoamp` 是面向 **纳米孔（Oxford Nanopore）PCR 扩增子** 的单倍型（haplotype）分析命令行工具。
它把一条扩增子内的所有读段（reads）还原成少量「单倍型序列」，给出每个单倍型的丰度、
相对参考序列的变异，以及——v0.1.0 新增——**这些变异在转录本层面的功能后果**
（同义 / 错义 / 无义 / 移码 / 提前终止 / 起始或终止密码子丢失等）。

设计目标是**可复现、可无网络运行、可被脚本调用**：

- 所有输出为制表符分隔的表格（TSV）+ JSON 清单（manifest），适合下游 `data.table`/pandas 处理；
- 去卷积（de novo 聚类）使用 DECIPHER，参考引导使用 minimap2，二者均随包提供；
- 功能注释优先联网获取权威注释，**但必须能明确地离线降级**，不允许静默出错。

## 2. 三种分析模式

| 模式 | 输入 | 做法 | 适用场景 |
|------|------|------|----------|
| **A**（`--mode A`） | 参考序列 + FASTQ | minimap2 比对到参考，再在比对结果上聚类/取一致序列 | **推荐**：已知扩增子序列、需要精确定位变异 |
| **B**（`--mode B`） | 仅 FASTQ | DECIPHER 从头聚类，无需参考 | 未知样本、快速分型、污染排查 |
| **C**（`--mode C`） | 参考序列 + FASTQ | 精确匹配（无编辑距离容忍） | 基线对照、评估其他模式的增益 |

功能测试中三种模式的 top-1 单倍型比例分别为 **A 0.6750 / B 0.7584 / C 0.1231**，模式 C 作为
下界基线说明「允许比对误差」是必要的。

## 3. 本版新增：功能注释（v0.1.0 的核心）

对应 `programs_dev_plan_1.md` §1.1 第 6 项「连接 GTF 等注释信息，判断变异属于移码、提前终止、missense 等」。

- **两条路线**
  - `--annotation-route genome`（默认）：仅联网拉取 Ensembl REST 注释与序列，**不要求用户自备 GTF / FASTA**。
  - `--annotation-route cds`：完全离线的降级路线，只需给出 CDS 区间，不联网。
- **只使用 Ensembl/GENCODE 体系**做结构注释；UCSC 仅用于取序列。刻意**不使用** UCSC 的
  `knownGene` / `ncbiRefSeq*` 轨道，避免 `uc*`/`NM_` 两套 ID 与 GENCODE 混用造成坐标错配。
- **不再接受本地 GTF/FASTA**：避免用户手里的注释版本与参考基因组不匹配而产出看似合理的错误结论。
- **缓存**：`$XDG_CACHE_HOME/nanoamp/ref`（可用 `NANOAMP_CACHE_DIR` 或 `--cache-dir` 覆盖），
  `--clear-cache` 清空，`--no-cache` 绕过缓存。
- **--ensembl-release** 默认取最新；**要复现结果必须显式固定 release**（本版验证使用 **116**）。

### 输出（在原有输出之外新增）

- `annotation.tsv`：每个「单倍型 × 转录本」一行，含 `consequence_en`（稳定枚举）与
  `consequence_zh`（中文列）双列，以及 CDS/蛋白层面的描述。
  `All` 布局下每行一个单倍型×转录本，并附加汇总列。
- `variants_annotation.tsv`：每个变异一行，含基因组坐标、转录本 CDS 坐标、
  密码子变化与氨基酸变化（`--annotation-detail` 时输出）。
- `--annotation-proteins`：额外输出参考/替代蛋白序列。
- `--list-transcripts`：只列出该扩增子重叠的候选转录本，不做后续分析。

### 四道自检（防止「看起来合理但坐标是错的」）

| 编号 | 检查 | 不通过时的行为 |
|------|------|----------------|
| **V1** | 参考蛋白交叉验证（在线 `sequence/id?type=cds` 翻译 vs 权威蛋白序列） | **中止**并报错（不产出注释） |
| **V2** | CDS 结构（长度、起始、终止、外显子区块自洽） | 拒绝该转录本并给出说明 |
| **V3** | 精确匹配锚定 + 反向推导回基因组坐标 | 锚定覆盖率 < 0.9 时**拒绝定位**并列出备选位点 |
| **V4** | 变异位置越界 / 删除跨越边界 | **报错退出**（早期版本会静默截断，已修） |

> 实测量级：在线取回的 ZNF8-201 CDS 为 1728 bp，而 GTF 记录为 1725 bp（差一个终止密码子）；
> 翻译后与权威参考蛋白 `identical()`，故以 575 aa 蛋白为锚定基准，而非裸 CDS 长度。

## 4. 主要修复（v0.1.0 内解决的真实缺陷）

1. **负链 `cds_pos` 条件写反**：`gp <= start && gp >= end` 恒为假，导致负链转录本上的变异被
   **静默丢弃**。已改为与链无关的区间包含判断 + 转录本方向偏移。合成镜像测试覆盖：
   `118→1`、`104→15`、`101→18`；多区块负链 `218→1`、`101→36`。
2. **退化 CDS 被判为「同义」**：空 CDS 或长度非 3 的倍数时，旧代码返回 `cds_ok=TRUE` 且
   `synonymous`。现在直接拒绝并附说明。
3. **变异应用越界**：`.annotation_apply_ops` 旧实现会静默追加/截断序列。现在对
   「越界位置」和「跨越末端的删除」明确报错。
4. **注释取回静默截断**：Ensembl region 接口在超出上限时返回 HTTP 200 但**截断数据**
   （实测请求 500 kb 只返回 331,965 bp）。现改为 ≤100 kb 分片 + 校验返回长度。
5. **限流报错形态**：Ensembl 限流表现为 `curl exit 56`。已加入节流（1.1 s）+ 指数退避 + URL 级缓存。
6. **单元测试偷偷联网**：测试套件此前会发起真实网络请求（约 60 s）。现在通过不可达 base URL +
   `retries=1L` 完全离线，约 2 s 跑完。
7. **`ShortRead` 依赖被移除**：它无条件 import `pwalign`（Biostrings ≥ 2.77.1 中已废弃的
   `pairwiseAlignment` 相关变更）。`R/io.R` 改为 base-R FASTQ 解析，支持按魔数识别 gzip。
8. **预编译二进制修正**：原先随包的 linux-x86_64 minimap2 实际是 `2.28-r1209`，已修正为
   **2.31-r1302** 并加入校验；samtools 不再随包，改用 `Rsamtools::asBam`。
9. **依赖安装策略**：优先 `pak::pak()`，回退 `install.packages()` / `BiocManager::install()`；
   conda 环境下 `fetch_dependencies.sh` 缺 `__glibc` 虚拟包的问题通过
   `CONDA_OVERRIDE_GLIBC=2.17` 解决。
10. **URL 中的 `&` 被 shell 吞掉**：R `system2` 会走 shell，改用 `curl -G --data-urlencode`。

## 5. 验证状态

| 项目 | 结果 |
|------|------|
| `R CMD check --no-manual --no-build-vignettes` | **Status: OK**（含 NOTE/WARNING 检查） |
| `testthat` 单元/集成测试 | 通过（含注释模块约 24 个离线用例） |
| 功能测试 | **168/168 ok**（3 模式 × 56 组，0 error） |
| 离线 `cds` 路线 | 通过（无网络环境下不触发任何请求） |
| ZNF8 在线注释 | 与本地 GENCODE v50 GTF + GRCh38 交叉验证一致（CDS 区块、575 aa 蛋白） |

## 6. 已知限制（请先读这一节）

- **`genome` 路线需要网络**。没有网络时会给出明确错误并非零退出，**不会**退化成静默的假结果。
  需要离线时请使用 `--annotation-route cds`。
- **注释结果依赖 Ensembl release**。默认取最新，不同时间运行可能得到不同注释。
  发表或复核请始终显式写 `--ensembl-release <N>`。
- **`all` 模式较慢**：受 Ensembl 节流限制（1.1 s/请求）。建议先用 `--list-transcripts` 选定转录本。
- **`protein_change` 为 HGVS 风格，但未经 HGVS 认证**，不应当作临床报告依据。
- **UTR 分类精度有限**：`overlap/id?feature=exon` 返回的是位点范围的外显子，
  因此 UTR 目前只做到「落在任一外显子内」的粒度。
- **负链仅由合成镜像测试覆盖**：`01_data` 中所有目标都定位在正链，缺少真实负链数据集验证。
- **TUI 尚未提供注释界面**（见 `TUI_plan.1.md` 的转录本多选）。

## 7. 文件清单

| 文件 | 体积 | SHA-256（前 12 位） |
|------|------|---------------------|
| `nanoamp-0.1.0-src.tar.gz` | 69,961,887 B（66.7 MiB） | `60fc2c543e5b` |
| `nanoamp-0.1.0-src.zip` | 69,983,098 B（66.7 MiB） | `5da9b79f553d` |
| `nanoamp-0.1.0-R-package.tar.gz` | 72,232 B（70.5 KiB） | `b7b9687978ec` |
| `SHA256SUMS` | — | 上述三个文件 |
| `manifest.tsv` | — | 版本 / 提交 / 构建时间 / 工具链 / 数据源 |

完整的 64 位校验和见 `SHA256SUMS` 与 `manifest.tsv`。

```
release/
├── README.md                     如何重新构建与发布
├── RELEASE_NOTES.md              本文件（同时作为 GitHub Release 正文）
├── manifest.tsv                  版本、提交、构建时间、大小、校验和、工具链
├── SHA256SUMS                    三个产物的 SHA-256
├── nanoamp-0.1.0-src.tar.gz      完整仓库源码归档（含 01_data/test_data，可复现）
├── nanoamp-0.1.0-src.zip         同上 ZIP 版
├── nanoamp-0.1.0-R-package.tar.gz  标准 R 包源码（R CMD INSTALL 用）
└── publish_github_release.sh     用 GitHub CLI/API 发布本 release 的脚本
```

归档由 `git archive 7422af9` 生成，因此归档内容**严格等于提交 `7422af9`**
（`release/` 自身经 `export-ignore` 排除）。`release/` 下的说明文件是本 tag 新增的，
不参与任何构建输入。

校验：

```bash
cd release && shasum -a 256 -c SHA256SUMS     # macOS
cd release && sha256sum -c SHA256SUMS         # Linux
```

## 8. 快速开始

```bash
# 1) 解压
tar xzf nanoamp-0.1.0-src.tar.gz && cd nanoamp-0.1.0

# 2) 安装 R 依赖（优先 pak，回退 install.packages/BiocManager）
Rscript 02_code/scripts/install_r_deps.R

# 3) 安装包本体
R CMD INSTALL nanoamp-0.1.0-R-package.tar.gz    # 或 R CMD INSTALL 02_code

# 4) 跑一遍自检
Rscript 02_code/scripts/run_functional_tests.R   # 期望 168/168 ok

# 5) 分析一个扩增子（模式 A）
Rscript 02_code/scripts/run_analysis.R --help

# 6) 在线功能注释（先看有哪些转录本）
Rscript 02_code/scripts/run_analysis.R \
  --mode A --ref <参考.fasta> --reads <reads.fastq> \
  --annotate --annotation-route genome --list-transcripts

# 7) 离线功能注释（降级路线）
Rscript 02_code/scripts/run_analysis.R \
  --mode A --ref <参考.fasta> --reads <reads.fastq> \
  --annotate --annotation-route cds --annotate-config 02_code/configs/example_cds.json
```

## 9. 引用与出处

使用本工具时请注明版本与注释来源，例如：

> nanoamp v0.1.0 (commit 7422af9). Functional annotation: Ensembl REST release 116
> (GENCODE-based), sequence from UCSC.

第三方组件与许可见 `03_dependence/licenses/` 与 `03_dependence/manifest.tsv`。
