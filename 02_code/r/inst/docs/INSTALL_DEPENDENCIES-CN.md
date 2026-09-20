# nanoamp 依赖安装与配置

本文说明如何在 Linux 上安装并配置 `minimap2`、`samtools`
以及 `nanoamp` 需要的 R 包。

## 1. 需要哪些依赖

| 依赖 | 类型 | 用途 |
|---|---|---|
| `minimap2` | 外部命令 | 方案 A/B 的 reads 比对 |
| `samtools` | 可选外部命令 | 兼容后备；默认使用 Rsamtools |
| R 包 | R 包 | 核心分析 |
| `DECIPHER` | 可选 R 包 | 方案 B 从头聚类 |

方案 C（原始精确匹配）不需要 `minimap2`。`samtools` 从来不是必需依赖，
因为 `Rsamtools::asBam()` 已经负责 SAM→BAM。

## 1.1 内置工具与 R 内后备

`nanoamp` 查找工具的顺序：

1. 环境变量 `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`；
2. `03_dependence/<os>-<arch>/bin/`；
3. `PATH`。

仓库已在 `03_dependence/linux-x86_64/bin/` 内置 minimap2 2.31。完整平台矩阵见
`03_dependence/README-CN.md`。Windows 依赖材料由姊妹仓库
`a_09_18_26_mapping_programs_dev_for_win` 维护。

没有 minimap2 二进制的平台（Linux ARM64、macOS）可以使用 R 内后端：

```r
run_haplotype_analysis(..., aligner = "r")
```

`samtools` 不是必需依赖：默认用 `Rsamtools::asBam()` 完成 SAM→BAM。
只有显式设置 `use_samtools = TRUE` 时才走 samtools。

## 2. Linux

### 方式 A：conda / mamba（推荐）

```bash
conda create -n nanoamp -c conda-forge -c bioconda minimap2 samtools
conda activate nanoamp

which minimap2
minimap2 --version

which samtools
samtools --version
```

然后在这个 R 环境中安装 R 包（见第 3 节）。

### 方式 B：系统包管理器

Debian / Ubuntu：

```bash
sudo apt-get update
sudo apt-get install -y minimap2 samtools
```

CentOS / Rocky / AlmaLinux：

```bash
sudo dnf install -y minimap2 samtools
```

### 验证

```bash
which minimap2
which samtools

Rscript -e 'library(nanoamp); nanoamp_cli("doctor")'
```

## 3. R 包

必需：

```r
install.packages(c(
  "Biostrings", "Rsamtools", "ShortRead", "IRanges", "Matrix",
  "data.table", "optparse", "jsonlite", "readxl"
))
```

如果 Bioconductor 包无法从 CRAN 安装：

```r
if (!requireNamespace("BiocManager", quietly = TRUE)) install.packages("BiocManager")
BiocManager::install(c("Biostrings", "Rsamtools", "ShortRead", "IRanges"))
```

可选：

```r
BiocManager::install("DECIPHER")             # 方案 B
```

## 4. 验证清单

```r
library(nanoamp)
nanoamp_cli("doctor")
```

期望输出：

```text
nanoamp version: 0.1.0
R version: ...
Rscript: ...
  Biostrings   TRUE
  ...
  DECIPHER     TRUE
  minimap2     /path/to/minimap2
  samtools     /path/to/samtools
```

需要确认：

- `minimap2` 显示路径而不是 `NOT FOUND`；
- `samtools` 是可选的，除非 `use_samtools = TRUE`，否则显示 `NOT FOUND` 也没关系；
- R 包显示 `TRUE`；
- `DECIPHER` 可以是 `FALSE`：方案 B 会自动降级，但建议安装。

## 5. 依赖缩减现状

以下改进已经实现：

1. 默认用 `Rsamtools::asBam()` 完成 SAM→BAM，`samtools` 命令变成可选；
2. `aligner = "r"` 提供 R 内成对比对后端，适合中小数据，以及没有
   minimap2 的 Linux ARM64 / macOS 平台；
3. `minimap2` 仍然是大数据量下的推荐后端。

只有显式设置 `use_samtools = TRUE` 时才需要 samtools。
