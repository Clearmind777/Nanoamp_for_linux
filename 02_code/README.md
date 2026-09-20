# nanoamp R 核心算法（v0.1）

本目录是纳米孔 PCR 产物单倍型分析程序的 R 核心实现，对应开发方案第 6 节的三种算法：

- **方案 A**：参考引导校正 + 单倍型计数（默认，推荐）
- **方案 B**：从头聚类 + 簇共识（DECIPHER 优先，缺失时降级为变异模式贪心聚类）
- **方案 C**：原始 reads 精确匹配（诊断模式）

本轮不包含 Web 版本、GUI、R 包封装和 GTF 功能注释。

## 环境要求

- R >= 4.2
- R 包：`Biostrings`、`Rsamtools`、`ShortRead`、`data.table`、`optparse`、`jsonlite`、`readxl`
- 外部命令：`minimap2`、`samtools`

检查环境：

```bash
Rscript 02_code/scripts/nanoamp.R doctor
```

## 快速开始

### RStudio

1. 打开项目根目录的 `nanoamp.Rproj`；
2. 编辑 `02_code/scripts/run_analysis.R` 顶部的 `CONFIG`；
3. 运行整个脚本。

### 命令行

```bash
# 单样本
Rscript 02_code/scripts/nanoamp.R call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --top-n 20 \
  --outdir 04_results/demo/E4-3

# 多样本批处理
Rscript 02_code/scripts/nanoamp.R batch \
  --sample-sheet samples.tsv \
  --mode A --outdir 04_results/batch
```

`sample-sheet.tsv` 至少包含 `sample`、`reads`、`reference` 三列。

### 测试数据软链接

```bash
Rscript 02_code/scripts/prepare_test_data.R
```

该脚本会重建 `01_data/ln_test_data` 下的软链接和 `manifest.tsv`。

### 单元测试与功能测试

```bash
Rscript 02_code/tests/testthat.R
Rscript 02_code/tests/run_functional_tests.R --outdir 04_results/test_run_1
```

## 输出文件

每次运行在 `--outdir` 下生成：

| 文件 | 说明 |
|---|---|
| `haplotypes.tsv` | 单倍型排名、reads 数、比例、置信区间、变异描述 |
| `haplotypes.fasta` | 前 n 条单倍型序列 |
| `variants.tsv` | 候选变异表；方案 A 列名兼容公司 `*.var.xls` |
| `qc.tsv` | reads 数、比对率、identity、覆盖度等 QC 指标 |
| `run_manifest.json` | 参数、参考序列、版本、输入文件 MD5 |
| `alignments.bam(.bai)` | 方案 A/B 的中间比对文件（可选保留） |

## 默认参数

| 参数 | 默认值 |
|---|---:|
| `top_n` | 20 |
| `min_reads` | 3 |
| `min_freq` | 0.02 |
| `min_identity` | 0.90 |
| `min_ref_coverage` | 0.90 |
| `homopolymer` | 4 |
| `strand_bias` | 0.90 |
| `identity_cutoff`（方案 B） | 0.99 |
| `min_cluster_reads`（方案 B） | 2 |
| `threads` | 4 |
