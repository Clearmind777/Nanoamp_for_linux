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

### 参考信息从哪来

**不需要手工下载任何文件。** 程序自己在 GRCh38 上定位扩增子，并从 Ensembl REST API
获取转录本结构（GENCODE/Ensembl 编号体系，ID 保持 `ENST`/`ENSG`）。只取所需切片
（每个扩增子几 KB），并缓存到 XDG 缓存目录：

```text
${XDG_CACHE_HOME:-~/.cache}/nanoamp/ref/
```

`--clear-cache` 清空，`--no-cache` 强制重取，`--cache-dir` 改位置。所用 Ensembl
release 会记入 `run_manifest.json`；需要固定参考版本时用 `--ensembl-release N`。

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
