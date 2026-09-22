# nanoamp

`nanoamp` 是一个用 R 编写的纳米孔 PCR 产物分析包。它可以把 reads 比对到目的序列，
校正测序错误，重建单倍型，并输出数量最多、比例最高的序列。

它主要回答这些问题：

- PCR 产物中有多少序列与目标产物完全一致？
- 其他序列是什么，各占多少比例？
- 哪些差异是真实变异，哪些是纳米孔测序错误？
- 多个变异是如何组合在同一条单倍型上的？

## 安装

### 1. 安装依赖

```r
install.packages(c(
  "Biostrings", "Rsamtools", "ShortRead", "IRanges", "Matrix",
  "data.table", "optparse", "jsonlite", "readxl"
))

# 方案 B 推荐安装
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
BiocManager::install("DECIPHER")

# 只有 R 内后端（aligner = "r"）和方案 B 的一致性序列标注需要成对比对。
# 在 Bioconductor >= 3.19 上 pairwiseAlignment() 已从 Biostrings 移到 pwalign。
# 该提供者是惰性解析的，只用 minimap2 的流程完全不需要它。
BiocManager::install("pwalign")
```

### 2. 安装 `nanoamp`

从构建好的 tar.gz 安装（例如 `make check` 生成的包；版本号按实际情况调整）：

```r
install.packages("05_builds/r/nanoamp_0.1.0.tar.gz", repos = NULL, type = "source")
```

从源码目录安装（`02_code/` 就是包根目录：本仓库不是纯 R 包仓库，包文件直接放在
这一层）：

```bash
R CMD INSTALL 02_code
```

开发模式安装：

```r
devtools::install("02_code")
```

### 3. 安装外部工具

`minimap2` 会优先从 `03_dependence/<os>-<arch>/bin/` 解析，其次才是 `PATH`。
`samtools` 不是必需依赖：默认用 `Rsamtools::asBam()` 完成 SAM→BAM。

Linux 下的详细安装与 PATH 配置说明见
[inst/docs/INSTALL_DEPENDENCIES-CN.md](inst/docs/INSTALL_DEPENDENCIES-CN.md)。

`nanoamp` 会优先使用 `03_dependence/<os>-<arch>/bin/` 中的工具，其次才是
`PATH`。仓库已内置 Linux x86_64 的 minimap2 2.31；平台支持矩阵和 R 内后备
方案见 `03_dependence/README-CN.md`。

```bash
minimap2 --version
# 可选：
# samtools --version
```

检查环境：

```r
library(nanoamp)
nanoamp::nanoamp_cli("doctor")
```

## 快速开始

```r
library(nanoamp)

res <- run_haplotype_analysis(
  reads     = "sample.fastq",
  reference = "target.fa",
  outdir    = "results/sampleA",
  mode      = "A",
  top_n     = 20
)

res$haplotypes   # 单倍型排行榜
res$variants     # 候选变异
res$qc           # 质控指标
```

输入要求：

- `reads`：FASTQ 或 FASTQ.GZ，纳米孔单端 reads；
- `reference`：包含目的序列的 FASTA；
- `outdir`：输出目录，不存在会自动创建。

## 三种分析模式

### 方案 A：参考引导校正（推荐）

先把 reads 比对到目的序列，发现候选变异，把没有通过过滤的差异当作测序错误
校正掉，再按校正后的序列分组计数。

适用于：

- 有可靠的目的序列；
- 需要定量的单倍型比例；
- 需要区分真实变异和纳米孔测序错误。

### 方案 B：从头聚类（探索性）

用 `DECIPHER::Clusterize` 对 reads 聚类，再对每个簇用 `DECIPHER::AlignSeqs`
做多序列比对，并用多数投票生成共识序列。

适用于：

- 没有可靠参考；
- 想快速了解主要序列分组；
- 可以接受“差异小于测序错误率的单倍型无法分开”这一限制。

如果 `DECIPHER` 不可用，方案 B 会自动降级为变异模式贪心聚类，并在
`qc.tsv` 中记录。

### 方案 C：原始精确匹配（诊断）

统计原始 reads 与参考正链或反向互补链完全一致的条数。它主要用于展示
纳米孔测序错误的影响，不推荐用于定量。

## 参数

查看默认参数：

```r
nanoamp_defaults()
```

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `top_n` | 20 | 输出前 n 条单倍型 |
| `min_reads` | 3 | 候选变异最低支持 reads 数 |
| `min_freq` | 0.02 | 候选变异最低频率 |
| `min_identity` | 0.90 | read 与参考的最低 identity |
| `min_ref_coverage` | 0.90 | read 覆盖参考的最低比例 |
| `homopolymer` | 4 | homopolymer 过滤阈值 |
| `strand_bias` | 0.90 | 链偏好过滤阈值 |
| `identity_cutoff` | 0.99 | 方案 B 聚类 identity 阈值 |
| `min_cluster_reads` | 2 | 方案 B 最小簇大小 |
| `max_msa_seqs` | 100 | 共识比对最多使用多少条序列 |
| `consensus_method` | `"decipher"` | `"decipher"` 或 `"medoid"` |
| `aligner` | `"minimap2"` | `"minimap2"` 或 `"r"`（R 内后备） |
| `use_samtools` | `FALSE` | 是否用 samtools 替代 Rsamtools 完成 SAM→BAM |
| `threads` | 4 | 线程数 |
| `keep_intermediates` | `TRUE` | 是否保留 BAM 等中间文件 |

## 输出文件

```text
outdir/
├── haplotypes.tsv
├── haplotypes.fasta
├── variants.tsv
├── qc.tsv
├── run_manifest.json
└── alignments.bam(.bai)     # 方案 A/B，keep_intermediates = TRUE 时保留
```

### haplotypes.tsv

| 列名 | 说明 |
|---|---|
| `rank` | 按支持 reads 数排名 |
| `haplotype_id` / `cluster_id` | 单倍型或簇编号 |
| `count` | 支持 reads 数 |
| `proportion` | 占有效 reads 的比例 |
| `ci_low`、`ci_high` | 95% Wilson 置信区间 |
| `is_reference` | 是否与参考序列一致 |
| `n_snv`、`n_ins`、`n_del` | 变异数量 |
| `length` | 单倍型长度 |
| `variants` | 变异描述；`.` 表示无变异 |

### variants.tsv

方案 A 的列与公司 `*.var.xls` 兼容：

```text
Chr  Pos  Ref  Alt  DP  Ref_dp  Alt_dp  Freq  DP4  Seq  Filter_Status  Filter_Reason
```

- `Freq` 是 0–1 的小数；
- `Ref` 或 `Alt` 中的 `-` 表示插入或缺失；
- `Filter_Status` 为 `PASS` 或 `FILTERED`。

### qc.tsv

两列 `metric` 和 `value`，包括 reads 数、比对率、平均 identity、覆盖度、
聚类方法、共识方法和 DECIPHER 版本。

## 命令行版本

R 包自带基于同一套 R 代码的命令行工具：

```bash
nanoamp doctor

nanoamp call \
  --reads sample.fastq \
  --reference target.fa \
  --mode A \
  --top-n 20 \
  --outdir results/sampleA

nanoamp batch \
  --sample-sheet samples.tsv \
  --mode A \
  --outdir results/batch
```

批量分析表是 TSV，至少包含：

```text
sample	reads	reference
```

可选列：`ref_label`。

在没有 minimap2 的平台上，可以用 `--aligner r` 选择 R 内比对后端。
仓库级启动器是 `02_code/cli/nanoamp`。

### 安装 `nanoamp` 命令

```bash
sh "$(Rscript --vanilla -e 'cat(system.file("scripts", "install_cli.sh", package = "nanoamp"))')" ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
nanoamp doctor
```

也可以直接在 R 中调用：

```r
library(nanoamp)
nanoamp_cli(c("call", "--reads", "sample.fastq", "--reference", "target.fa",
              "--outdir", "results/sampleA"))
```

## 外部工具与 R 内后端

`aligner = "minimap2"` 会优先使用内置的 minimap2 二进制。
ARM、macOS 或没有 minimap2 的机器上可以改用：

```r
run_haplotype_analysis(..., aligner = "r")
```

R 内后端使用 Biostrings 成对比对，不需要外部工具；速度较慢，适合中小扩增子。

成对比对的提供者是**惰性解析**的：第一次真正用到时才解析并缓存结果。

- `aligner = "minimap2"`（默认）完全不会碰到它，所以即使没装任何成对比对提供者，
  包也能正常加载并跑完整个分析；
- `aligner = "r"`，以及方案 B 对每个簇一致性序列的标注，会在第一次调用时解析；
- 装了 `pwalign` 就优先用它，否则回退到 Biostrings；只有当两者都不提供
  `pairwiseAlignment()` 时，才会在**调用处**报错。`qc.tsv` 会记录实际使用的
  提供者（从未用到该后端时为 `NA`）。

`samtools` 不是必需依赖：默认用 `Rsamtools::asBam()` 完成 SAM→BAM。
只有显式设置 `use_samtools = TRUE` 才会调用 samtools。

## RStudio 使用流程

1. 打开 `02_code/nanoamp.Rproj`；
2. 修改 `02_code/scripts/run_analysis.R` 顶部的 `CONFIG`；
3. 运行整个脚本。

脚本会自动寻找项目根目录，并把结果写到 `04_results/r/`。

## 使用测试数据

公司交付的文件名很长，因此用 `01_data/manifest.tsv` 保存“逻辑名 → 真实文件”的
映射（`dataset` / `sample` / `role`）。manifest 不存数据，也不需要任何预处理；
如需从原始交付文件重建：

```bash
Rscript 02_code/scripts/prepare_test_data.R
# 或：make test-data
```

查询某个样本：

```r
m <- data.table::fread("01_data/manifest.tsv")
m[dataset == "TSM20260826" & sample == "E4-3", .(role, cluster, path)]
```

示例：

```r
library(nanoamp)
res <- run_haplotype_analysis(
  reads     = "01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq",
  reference = "01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.1.seq",
  outdir    = "04_results/r/demo/E4-3",
  mode      = "A"
)
```

## 测试与验证

```r
# 已安装包的单元测试
testthat::test_check("nanoamp")

# 开发模式
devtools::test("02_code")
```

完整功能测试（输入全部按 `01_data/manifest.tsv` 解析）：

```bash
Rscript 02_code/scripts/run_functional_tests.R \
  --outdir 04_results/r/test_run_local --modes A,B,C --threads 4
# 或：make functional-test
```

本包已通过 `R CMD check`，当前结果为 `Status: OK`。

## 常见问题

| 现象 | 解决办法 |
|---|---|
| 找不到 `minimap2` | 安装 minimap2 并加入 `PATH` |
| 找不到 `samtools` | 通常不需要：默认使用 `Rsamtools`；只有 `use_samtools = TRUE` 才需要 samtools |
| 方案 B 太慢 | 降低 `max_msa_seqs`、增加 `threads`，或改用方案 A |
| 方案 B 分不开相近单倍型 | 这是低于测序错误率时的固有限制，请用方案 A |
| 没有安装 `DECIPHER` | 方案 B 会自动降级为贪心聚类；建议安装 DECIPHER |
| 报错 `pairwiseAlignment` is not an exported object from Biostrings | 只有 `aligner = "r"` 和方案 B 标注需要成对比对。Bioconductor >= 3.19 已把它移到 `pwalign`，用 `BiocManager::install("pwalign")` 安装即可；默认的 minimap2 流程不受影响 |
| 方案 C 比例很低 | 纳米孔 reads 有错误，请用方案 A |

## 许可证

MIT。
