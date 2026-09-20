# nanoamp

`nanoamp` 用于分析纳米孔 PCR 产物的测序数据。给定 FASTQ 和目的序列，它会校正
测序错误、重建单倍型，并输出数量最多、比例最高的序列。

本仓库是 `nanoamp` 的 Linux 命令行发行版，包含 `nanoamp` R 包、`nanoamp`
命令行程序，以及随附的 Linux x86_64 `minimap2` / `samtools` 二进制文件。
本仓库不包含图形界面。

## 安装

所有外部依赖均使用 conda 安装。

```bash
# 1. 创建环境（R、R 包、minimap2 和 samtools）
conda create -n nanoamp -c conda-forge -c bioconda \
  r-base minimap2 samtools \
  r-data.table r-optparse r-jsonlite r-readxl \
  bioconductor-biostrings bioconductor-rsamtools bioconductor-shortread \
  bioconductor-iranges bioconductor-decipher
conda activate nanoamp

# 2. 安装本仓库自带的 nanoamp R 包
R CMD INSTALL 02_code/r

# 3. 验证安装
sh 02_code/cli/nanoamp doctor
```
