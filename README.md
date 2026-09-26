# nanoamp

**中文** | [English](README-EN.md)

`nanoamp` 用于分析纳米孔 PCR 产物的测序数据。给定 FASTQ 和目的序列，它会校正
测序错误、重建单倍型，并输出数量最多、比例最高的序列。

本仓库是 `nanoamp` 的命令行发行版，包含 `nanoamp` R 包、`nanoamp` 命令行程序，
以及**为四个平台全部预置好的 `minimap2`**（Linux 与 macOS，x86_64 与 arm64）。
本仓库不包含图形界面。

它还能把每条序列差异翻译成生物学结论（**移码 / 提前终止 / missense / 同义**，
以及 UTR、内含子、剪接区等）。这需要转录本结构，程序会**联网按需获取**——
你不需要准备任何 GTF 或基因组 FASTA。详见[功能注释](#功能注释)。

## 安装

比对程序不需要安装：`03_dependence/<os>-<arch>/bin/minimap2` 已在仓库内，刚克隆
下来即可使用，离线、不需要 conda 或任何包管理器。只有 R 包需要安装，按你的机器
任选一种方式即可。

### 方式 A —— conda（顺带装好 R）

```bash
# 1. 创建环境（R 与 R 包；minimap2 用仓库里预置的）
conda create -n nanoamp -c conda-forge -c bioconda \
  r-base \
  r-data.table r-optparse r-jsonlite r-readxl \
  bioconductor-biostrings bioconductor-rsamtools bioconductor-shortread \
  bioconductor-iranges bioconductor-decipher
conda activate nanoamp

# 2. 安装本仓库自带的 nanoamp R 包
#    （02_code/ 就是包根目录）
R CMD INSTALL 02_code

# 3. 验证安装
sh 02_code/cli/nanoamp doctor
```

### 方式 B —— 用你已有的 R

不需要 conda。辅助脚本优先调用 `pak::pak()`：pak 会一次性解析 CRAN 与
Bioconductor 的依赖图，并复用 CRAN / Bioconductor 为 macOS（arm64 与 x86_64）
和 Windows 发布的预编译二进制；若 pak 缺失，则回退到 `install.packages()` +
`BiocManager::install()`。

```bash
# 1. 安装 R 依赖（pak 优先，回退 install.packages / BiocManager）
Rscript 02_code/scripts/install_r_deps.R

# 2. 安装包并验证
R CMD INSTALL 02_code
sh 02_code/cli/nanoamp doctor
```

`doctor` 会打印：识别到的平台、依赖目录、可见的 R 包，以及 `minimap2` /
`samtools` 的解析路径。预置二进制到位时，`minimap2` 解析到的是仓库内部的路径：

```text
platform: macos-arm64
dependence directory: /path/to/repo/03_dependence
  minimap2     /path/to/repo/03_dependence/macos-arm64/bin/minimap2 (2.31-r1302)
  samtools     NOT FOUND (optional; Rsamtools is used by default)
```

`samtools` 故意不预置：`Rsamtools::asBam()` 就能完成 SAM→BAM。如果某台机器的
`PATH` 里本来就有 `samtools`，`use_samtools = TRUE` 仍会用它。预置二进制是如何
核实“只依赖操作系统库”的，见 `03_dependence/README-CN.md`。

## 两种不同的“比对”

`minimap2` 和 `pwalign` 不是同一件事的两个可选方案：

- **reads 比对**：`minimap2` 把每条 read 贴到目的序列上，并给出它携带的变异。
  这是默认方式（`aligner = "minimap2"`），方案 A/B 走的就是这条路；
- **成对比对**：Biostrings（Bioconductor >= 3.19 上是 `pwalign`）只做“一条序列
  对一条序列”的比较。只有 `aligner = "r"`（内置二进制与宿主不匹配时的 R 内后端）
  以及方案 B 对每个簇一致性序列的标注会用到它。

成对比对的提供者是**惰性解析**的：第一次真正调用时才解析。只用 minimap2 的流程
完全不会碰到它，所以即使没有安装 `pwalign`，包也能正常加载并跑完分析；
`qc.tsv` 会记录实际使用的提供者，从未用到该后端时记为 `NA`。详见
`02_code/README-CN.md`。

## 快速开始

```bash
# 查看某个样本的全部文件（逻辑名 -> 真实文件）
awk -F'\t' '$1=="TSM20260826" && $2=="E4-3"' 01_data/manifest.tsv

# 运行单个样本
sh 02_code/cli/nanoamp call \
  --reads 01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq \
  --reference 01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.1.seq \
  --mode A --top-n 20 \
  --outdir 04_results/r/demo/E4-3
```

分析模式、全部参数、输出字段和 R 接口见 `02_code/README-CN.md`；
目录结构见 `02_code/ARCHITECTURE-CN.md`。

## 输入数据要求

本节是**硬性约定**：按这里准备数据，程序不会因为格式或命名问题失败；不按这里准备，
失败信息会说清楚是哪一项不合规。以下每一条都与代码行为一致，不是建议性描述。

### 1. 最低限度要提供什么

| # | 必需 | 内容 | 说明 |
|---|---|---|---|
| 1 | ✅ | **一个 FASTQ 文件** | 该样本的全部 reads，未比对、未纠错的原始或质控后序列 |
| 2 | ✅ | **一个参考序列文件（FASTA）** | 该扩增子本身的序列，**不是全基因组** |
| 3 | ✅ | **一个输出目录路径** | 由 `--outdir` 给出；不存在会自动创建 |

就这三项。**不需要**提供 GTF、基因组 FASTA、比对 BAM、变异统计表或任何注释文件——
功能注释所需的转录本结构由程序联网获取（见[功能注释](#功能注释)）。

三种分析模式对输入的要求完全一样，区别只在算法：

| 模式 | 需要参考序列吗 | 备注 |
|---|---|---|
| **A**（参考引导，默认） | 需要 | 推荐；能给出变异在扩增子上的精确坐标 |
| **B**（de novo 聚类） | 仍然需要传入 | 参考只用于写标签与计算覆盖率，聚类本身不依赖它 |
| **C**（精确匹配） | 需要 | 只做原始 reads 计数，**不跑功能注释** |

### 2. 数据文件怎么命名

**程序不解析文件名。** 它只按你传给 `--reads` / `--reference` 的路径读取内容，
因此文件名可以是任何合法的文件名（含中文），不会因为命名不符合某种规则而失败。

命名规则**只用于人和脚本的可追溯性**，不是程序要求。仍然强烈建议：同一个样本的
reads 与参考序列使用**同一个前缀**，用固定后缀区分，例如：

```text
<样本名>_<批次>_<日期>-<批次号>-<条码>-<孔位>.fastq   # reads
<样本名>_<批次>_<日期>-<批次号>-<条码>-<孔位>.1.seq   # 参考序列（扩增子）
```

这正是本仓库测试数据的命名方式，例如：

```text
E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq   ← --reads
E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.1.seq   ← --reference
```

这样命名之后，`--reads` 与 `--reference` 的关系一眼可辨，批处理表也不容易写错。
`01_data/manifest.tsv` 是**本仓库内部**用来把「逻辑名（dataset/sample/role）」映射到
真实文件名的表，属于测试脚本的便利设施，**你不需要提供它**。

### 3. FASTQ 格式要求

接受 `.fastq`、`.fq`，以及 gzip 压缩的 `.fastq.gz` / `.fq.gz`。
压缩与否按**文件头魔数（`1f 8b`）**判断：扩展名不是 `.gz` 时会先探魔数，
是 `.gz` 时由 R 的 `gzfile()` 同样按魔数决定是否解压。两种情况下都无需你手动解压，
也无需把扩展名改成 `.gz`。

必须满足：

| 要求 | 不合规时的行为 |
|---|---|
| **每条记录正好 4 行**：`@` 头、序列、`+` 分隔、质量 | `Malformed FASTQ (N lines is not a multiple of 4)` 并**非零退出** |
| 每第 1 行以 `@` 开头、每第 3 行以 `+` 开头 | `Malformed FASTQ (expected a '@' header and a '+' separator ...)` 并非零退出 |
| 每条记录的序列必须是**一行** | 同上——**换行折叠的序列不支持** |
| 文件非空 | `Mode A: no aligned reads` 并非零退出 |

关于质量串（第 4 行）：

- **必须存在**，但**内容不参与任何计算**。程序不按质量过滤、不做质量加权、
  不输出质量指标；比对与去卷积只用序列。
- 因此质量串**不要求与序列等长**，用 `IIII…` 之类的占位串也能跑通。

关于序列本身：

- 大小写不敏感（读入后统一转大写）。
- 允许含 `N` 等简并碱基；含 `N` 的位置按不匹配处理。
- 单条 read 长度没有硬性下限，但明显短于扩增子的片段更容易被比对过滤掉。

### 4. 参考序列（FASTA）要求

| 要求 | 说明 / 不合规时的行为 |
|---|---|
| 必须是 **FASTA** 格式 | 传 `.seq`、`.fa`、`.fasta`、`.fas` 都可以——**按内容解析，不看扩展名**（本仓库测试数据的参考序列就是 `.seq`）。内容不是 FASTA 时 Biostrings 会报错并非零退出，例如 `">" expected at beginning of line 1` |
| **只取第一条记录** | 文件里有第二条及以上记录时，**静默忽略**（不报错）。请确保要用的序列是第一条 |
| 至少一条非空序列 | 空文件：`Reference sequence is empty` 并非零退出 |
| 必须是**该扩增子本身** | 若传全基因组，A 模式能比对但坐标、功能注释与产物长度都会失去意义 |
| 建议与实测 PCR 产物长度相当 | 参考序列的长度会写进 `qc.tsv` 的 `reference_length` 并参与覆盖率计算，长度明显不符会直接反映在 `mean_coverage` 上 |

参考序列决定**所有输出坐标的原点**：`variants.tsv` 的位置、`haplotypes.fasta` 的
比对基准，以及功能注释的 CDS 坐标，全部相对于你传入的这条序列。**换参考就要重新确认
坐标**，尤其是 `cds` 路线的 JSON 配置。

### 5. 输出目录与命名

`--outdir` 指向的目录不存在时会被创建。每次运行会在其下写入固定的一组文件
（`haplotypes.tsv`、`haplotypes.fasta`、`variants.tsv`、`qc.tsv`、
`run_manifest.json`；启用注释后另有 `annotation.tsv`）。**同一目录重复运行会被覆盖**，
因此建议一个样本一个目录：

```bash
--outdir 04_results/r/demo/E4-3
```

`run_manifest.json` 记录了本次运行的 `reference`（路径、md5、长度）与 `reads_md5`，
可以直接用来自查「这次结果对应的是哪两份输入」。

### 6. 批量输入：样本表（可选）

样本多时用 `batch` 子命令，传入一个**制表符分隔（TSV）**文件：

```bash
sh 02_code/cli/nanoamp batch --sample-sheet samples.tsv --outdir 04_results/batch --mode A
```

```text
sample   reads                       reference                   ref_label
E4-3     data/E4-3_H08.fastq         data/E4-3_H08.1.seq          E4-3 自身共识
WT       data/WT_B11.fastq           data/WT_B11.1.seq            WT
clone_3  data/clone_3_F12.fastq      data/WT_B11.1.seq            WT（作为参考）
```

| 列 | 必需 | 说明 |
|---|---|---|
| `sample` | ✅ | 样本名；**同时作为输出子目录名**，因此不要含 `/` |
| `reads` | ✅ | FASTQ 路径（相对当前工作目录或绝对路径） |
| `reference` | ✅ | 参考序列路径 |
| `ref_label` | 否 | 写进输出的参考标签；缺省时用文件名 |

表头必须正好包含 `sample`、`reads`、`reference` 三列，否则报错并列出必需列名。
每个样本写入 `<outdir>/<sample>/`，另生成一份汇总。

### 7. 功能注释（可选）对输入的额外要求

不传 `--annotate-config` 时本节完全不适用，输出与不启用注释时逐字节一致。

需要另给一个 JSON 配置文件，**二选一**：

- `"route": "genome"`（默认，**需要联网**）：程序自行在 GRCh38 上定位扩增子并取
  Ensembl 注释，你不需要提供任何注释文件。
- `"route": "cds"`（**完全离线**）：在配置里直接给出 CDS 区间。

`cds` 路线的坐标要求（最容易出错，务必确认）：

| 要求 | 说明 |
|---|---|
| 坐标系 | 相对**你传给 `--reference` 的那条序列**，**1-based、两端闭区间** |
| 长度 | `end - start + 1` **必须是 3 的倍数** |
| 链方向 | `"strand": "+"` 或 `"-"`；`"-"` 时坐标仍按参考序列的正向编号写 |
| 长度不是 3 的倍数时 | 注释**被跳过**，运行仍以退出码 0 结束，但 `qc.tsv` 写入 `annotation_available = FALSE` 与 `annotation_skip_reason`，`run_manifest.json` 写入 `annotation.available = false` 与 `skipped_transcripts` |
| 多个转录本中部分被跳过时 | `available` 仍为 `true`，但 `qc.tsv` 的 `n_transcripts_skipped` 与 `annotation_skip_reason`、`run_manifest.json` 的 `skipped_transcripts` 会逐条记录 |

可直接使用的例子：`02_code/configs/example_online.json` 与
`02_code/configs/example_cds.json`（后者已用一个真实扩增子的最长 ORF 填好坐标）。
字段全集见 `02_code/configs/README.md`。

### 8. 常见的输入错误与对应信息

| 你会看到 | 原因 |
|---|---|
| `FASTQ file not found: ...` | `--reads` 路径不存在 |
| `Reference sequence not found: ...` | `--reference` 路径不存在 |
| `Malformed FASTQ (N lines is not a multiple of 4)` | 记录不满 4 行，或有折叠的序列 |
| `Malformed FASTQ (expected a '@' header ...)` | 第 1 行不是 `@`、第 3 行不是 `+`，或文件不是 FASTQ |
| `Reference sequence is empty` | 参考序列文件是空的 |
| `Mode A: no aligned reads` | FASTQ 为空，或没有一条 read 通过 `--min-identity` / `--min-ref-coverage` |
| `sample-sheet must contain columns: ...` | 批处理表缺必需列 |
| `Annotation config not found: ...` | `--annotate-config` 路径写错（注意：`--annotate` 这类缩写不会被接受） |
| 输出里 `annotation_available = FALSE` | 注释被请求但未产出；具体原因见同行的 `annotation_skip_reason` |

以上输入类错误都会以**非零退出码**结束，不会产出看似正常的半成品结果。

## 功能注释

加 `--annotate-config` 即启用功能注释：在常规输出旁写出 `annotation.tsv`，并给 `qc.tsv`
追加后果统计列。不加该参数则一切与现在完全一致。

```bash
# 这个扩增子落在哪些转录本上？（不需要注释配置）
sh 02_code/cli/nanoamp call \
  --reads sample.fastq --reference amplicon.fa --outdir out \
  --list-transcripts

# 按 MANE Select 转录本注释
sh 02_code/cli/nanoamp call \
  --reads sample.fastq --reference amplicon.fa --outdir out \
  --annotate-config 02_code/configs/example_online.json

# ……或注释全部重叠转录本
sh 02_code/cli/nanoamp call ... --annotate-config cfg.json --transcript all

# 附带蛋白序列，以及每个变异的逐条明细
sh 02_code/cli/nanoamp call ... --annotate-config cfg.json \
  --annotation-proteins --annotation-detail
```

注释产出：

| 文件 | 内容 |
|---|---|
| `annotation.tsv` | 每个单倍型 × 每个所选转录本一行（中英双列后果、蛋白变化） |
| `variants_annotation.tsv` | 仅 `--annotation-detail`：每个变异一行，含密码子与氨基酸变化 |
| `qc.tsv` | 追加注释统计（转录本数、各类后果计数、冲突数） |
| `run_manifest.json` | 追加 `annotation` 段（来源、Ensembl release、配置、转录本校验结果） |

只要有转录本被跳过就会留痕（控制台的 WARN 在运行结束后无法追溯）：`qc.tsv` 写
`n_transcripts_annotated` / `n_transcripts_skipped` 与 `annotation_skip_reason`，
`run_manifest.json` 写 `annotation.skipped_transcripts`，逐条给出转录本与原因。
全部失败时（例如 CDS 长度不是 3 的倍数）额外写 `annotation_available = FALSE` /
`annotation.available = false`；两种情况的退出码都是 0，因为序列分析本身是成功的。
**判断注释覆盖了哪些转录本请看这些字段，不要只看 `annotation.tsv` 里出现了几条。**

### 参考信息从哪来

**不需要手工下载任何文件。** 程序自己在 GRCh38 上定位扩增子，并从 Ensembl REST API
获取转录本结构（GENCODE/Ensembl 编号体系，ID 保持 `ENST`/`ENSG`）。只取所需切片
（每个扩增子几 KB），并缓存到 XDG 缓存目录：

```text
${XDG_CACHE_HOME:-~/.cache}/nanoamp/ref/
```

`--clear-cache` 清空，`--no-cache` 强制重取，`--cache-dir` 改位置。所用 Ensembl
release 会记入 `run_manifest.json` 的 `annotation.ensembl_release`，复核时以它为准。
**v0.1.0 还没有 `--ensembl-release`**（钉死历史 release 需要 Ensembl 归档主机，留待后续版本）。

### 两条路线，同一套管线

| 路线 | 适用 | 依赖 |
|---|---|---|
| `genome`（默认） | 常规使用：程序自行定位扩增子与转录本 | 需要联网 |
| `cds` | 扩增子参考不是纯 GRCh38 片段，或机器离线 | **什么都不需要**：自己给 `cds.start` / `cds.end` |

`cds` 路线是离线后备路径：只做翻译，**完全不需要网络**
（示例见 `02_code/configs/example_cds.json`）。

### 后果词表（中英双列）

后果同时给出英文枚举与中文标签（`consequence_en` / `consequence_zh`）：
下游代码可按稳定的英文值筛选，表格本身保持可读。

| 英文 | 中文 |
|---|---|
| `frameshift` | 移码 |
| `stop_gained` | 提前终止 |
| `stop_lost` | 终止丢失 |
| `start_lost` | 起始丢失 |
| `inframe_insertion` / `inframe_deletion` | 整码插入 / 整码缺失 |
| `missense` | 错义 |
| `synonymous` | 同义 |
| `splice_region` | 剪接区 |
| `5_prime_UTR` / `3_prime_UTR` | 5'UTR / 3'UTR |
| `intron` | 内含子 |
| `outside_cds` | CDS 之外 |

每个单倍型另给 `consequence_any_transcript`（所选转录本中最严重的后果）与
`transcript_conflict`（同一变异在不同转录本下后果不同）——后者是"转录本选错"最直观的报警。

### 每次运行都会自检

1. **V1** —— 把我们拼出的 CDS 翻译后与 Ensembl 提供的官方蛋白对拍；不一致就**中止**，
   而不是在错误阅读框上继续输出后果；
2. **V2** —— CDS 长度、起始密码子、终止密码子与块布局；
3. **V3** —— 扩增子位置由**精确匹配锚点**推导，坐标由锚点反推，因此"部分匹配的参考"
   不会悄悄让所有坐标偏移。

若参考服务不可达，程序**直接报错并以非零状态退出**，绝不会静默地返回一份没有注释的结果。

## 仓库结构

```text
00_materials/    委托、开发方案与历次工作报告
01_data/         测试数据（test_data/ 原始交付 + manifest.tsv 名字映射）
02_code/         R 包源码 + CLI 启动器 + 共享契约 + 辅助脚本
03_dependence/   为四个平台预置的 minimap2 与各平台说明
04_results/      运行结果（除 README 外不进 Git）
05_builds/       R CMD build / check 产物
release/         发布产物与说明（大体积归档不进 Git，见 release/README.md）
```

发布：`make release` 从当前 tag 构建 `release/` 下的全部产物，
`make release-check` 只校验，`make release-publish` 推送到 GitHub Release
（需要 `gh auth login` 或 `GH_TOKEN`）。当前版本见 `release/RELEASE_NOTES.md`。

## 开发平台

本仓库在不止一台机器上开发；代码本身不含平台相关逻辑，而从报告 9 起每个支持的
平台都有自己的预置 `minimap2`。

| 平台 | 预置二进制 | 状态 |
|---|---|---|
| Linux x86_64 | `linux-x86_64/bin/minimap2`（glibc >= 2.14） | 最初开发平台，报告 1–7 的验证平台 |
| Linux arm64 | `linux-arm64/bin/minimap2`（glibc >= 2.17） | 已预置；需在 Linux arm64 宿主上执行 |
| macOS x86_64 | `macos-x86_64/bin/minimap2` | 已预置；在 Apple Silicon 上也可通过 Rosetta 2 运行 |
| macOS arm64 | `macos-arm64/bin/minimap2` | 当前验证平台，见报告 8 |

在 macOS arm64 上做一次完整本地验证：

```bash
make test             # testthat 单元测试
make check            # R CMD build + R CMD check
make cli              # sh 02_code/cli/nanoamp doctor
make functional-test  # 全部数据集 × 模式 A/B/C，输入按 01_data/manifest.tsv 解析
```

最近一次 macOS arm64 验证结果（R 4.5.3、Biostrings 2.78.0、pwalign 1.6.0、
DECIPHER 3.6.0、**仓库预置的** `minimap2` 2.31，`PATH` 中没有 conda 提供的工具）：

| 检查 | 结果 |
|---|---|
| `R CMD INSTALL 02_code` | 成功 |
| `testthat` 单元测试 | 全部通过，无跳过 |
| `R CMD check --no-manual` | **Status: OK** |
| `nanoamp doctor` | 平台识别为 `macos-arm64`，R 包全 TRUE，`minimap2` 解析到 `03_dependence/macos-arm64/bin/` |
| `run_functional_tests.R`（3 数据集 × 32 样本 × 模式 A/B/C） | **168/168 全部 ok** |

在可与 Linux x86_64 基线对比的指标上，跨平台结果一致：方案 A 与公司变异表
位置/等位基因完全一致的样本为 **22/23**（与 `work_report.1.md` 相同），方案 C
原始精确匹配占比中位数为 **12.0%**（同样相同）。

面向 Linux x86_64 的历史文档原样保留在 `00_materials/`（工作报告属于日志，不做
改写；报告 8、9 列出了发生变化的路径），各平台依赖说明保留在
`02_code/inst/docs/INSTALL_DEPENDENCIES-CN.md`。英文版见 `README-EN.md`。
