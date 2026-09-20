# nanoamp 依赖安装与配置

本文说明如何在 Linux 和 Windows 上安装并配置 `minimap2`、`samtools`
以及 `nanoamp` 需要的 R 包。

## 1. 需要哪些依赖

| 依赖 | 类型 | 用途 |
|---|---|---|
| `minimap2` | 外部命令 | 方案 A/B 的 reads 比对 |
| `samtools` | 外部命令 | 方案 A/B 的 SAM/BAM 排序与索引 |
| R 包 | R 包 | 核心分析 |
| `DECIPHER` | 可选 R 包 | 方案 B 从头聚类 |
| `shiny`、`bslib`、`DT` | 可选 R 包 | GUI |

方案 C（原始精确匹配）不需要 `minimap2` 和 `samtools`。

## 1.1 内置工具与 R 内后备

`nanoamp` 查找工具的顺序：

1. 环境变量 `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`；
2. `03_dependence/<os>-<arch>/bin/`；
3. `PATH`。

仓库已在 `03_dependence/linux-x86_64/bin/` 内置 minimap2 2.31。完整平台矩阵见
`03_dependence/README-CN.md`。

没有 minimap2 二进制的平台（Windows、ARM）可以使用 R 内后端：

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

然后在这个 R 环境中安装 R 包（见第 4 节）。

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

## 3. Windows

### 方式 A：conda / mamba（推荐）

1. 安装 Miniforge 或 Miniconda；
2. 打开 **Miniforge Prompt** 或 **Anaconda Prompt**；
3. 创建环境：

```bat
conda create -n nanoamp -c conda-forge -c bioconda minimap2 samtools
conda activate nanoamp

where minimap2
where samtools
```

4. 在同一环境中安装 R，或使用系统 R：

```bat
conda install -c conda-forge r-base
```

5. 从已激活的 conda 命令行启动 R 或 RStudio；或者把环境中的
   `Library\bin` 和 `Scripts` 目录加入 Windows `PATH`。

路径示例：

```text
C:\Users\<你的用户名>\miniforge3\envs\nanoamp\Library\bin
C:\Users\<你的用户名>\miniforge3\envs\nanoamp\Scripts
```

### 方式 B：预编译二进制

- `minimap2`：从官方 release 下载 Windows x64 版本，解压出 `minimap2.exe`，
  例如放到 `C:\tools\minimap2`；
- `samtools`：官方 Windows 二进制支持有限，推荐使用 conda（方式 A）或 WSL2（方式 C）；
- 把包含 `.exe` 的目录加入 `PATH`。

### 方式 C：WSL2

1. 安装 WSL2 和 Ubuntu；
2. 在 WSL 中用 apt 或 conda 安装（见第 2 节）；
3. 在 WSL 中运行分析。适合无法获得原生 Windows 二进制的情况。

### 在 Windows 配置 PATH

1. 打开 **系统属性 -> 环境变量**；
2. 编辑 `Path`；
3. 加入包含 `minimap2.exe`、`samtools.exe` 的目录；
4. 确定后**重启 RStudio / 终端**；
5. 在 R 中验证：

```r
Sys.which("minimap2")
Sys.which("samtools")
library(nanoamp)
nanoamp_cli("doctor")
```

### Windows 常见坑

- **conda 环境没有激活**：在环境外启动 R，看不到 conda 里的工具；
- **PATH 未刷新**：修改 PATH 后必须重启 RStudio；
- **路径有空格或中文**：建议放到 `C:\tools\...`；
- **Windows SmartScreen**：如果提示拦截下载的 exe，需要手动允许；
- **多个 R 版本**：用 `Rscript -e 'cat(R.home())'` 确认当前 R，
  并确保 R 包装到了同一个 R 中。

## 4. R 包

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
install.packages(c("shiny", "bslib", "DT"))  # GUI
```

## 5. 验证清单

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

- `minimap2`、`samtools` 显示路径而不是 `NOT FOUND`；
- R 包显示 `TRUE`；
- `DECIPHER` 可以是 `FALSE`：方案 B 会自动降级，但建议安装。

## 6. 后续减少外部依赖的计划

1. 用 `Rsamtools`（`asBam`、`sortBam`、`indexBam`）替代 `samtools` 命令；
2. 增加 R 内比对后端（`aligner = "r"`），适合中小数据；
   `minimap2` 继续作为大数据量的默认后端。
