# nanoamp

`nanoamp` 用于分析纳米孔 PCR 产物的测序数据。给定 FASTQ 和目的序列，它会校正
测序错误、重建单倍型，并输出数量最多、比例最高的序列。

本仓库是 `nanoamp` 的命令行发行版，包含 `nanoamp` R 包、`nanoamp` 命令行程序，
以及（针对 Linux x86_64）随附的 `minimap2` / `samtools` 二进制文件。
本仓库不包含图形界面。

## 安装

所有外部依赖均使用 conda 安装。同一套命令适用于 Linux x86_64、Linux arm64 和
macOS（Intel 与 Apple Silicon）。

```bash
# 1. 创建环境（R、R 包、minimap2 和 samtools）
conda create -n nanoamp -c conda-forge -c bioconda \
  r-base minimap2 samtools \
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

`doctor` 会打印：识别到的平台、依赖目录、可见的 R 包，以及 `minimap2` /
`samtools` 的解析路径。

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

## 仓库结构

```text
00_materials/    委托、开发方案与历次工作报告
01_data/         测试数据（test_data/ 原始交付 + manifest.tsv 名字映射）
02_code/         R 包源码 + CLI 启动器 + 共享契约 + 辅助脚本
03_dependence/   随附外部工具（Linux x86_64）与各平台说明
04_results/      运行结果（除 README 外不进 Git）
05_builds/       R CMD build / check 产物
```

## 开发平台

本仓库在不止一台机器上开发；代码本身不含平台相关逻辑，但随附的二进制文件和
已验证过的环境是分平台的。

| 平台 | 状态 | 说明 |
|---|---|---|
| Linux x86_64 | 最初开发平台 | 自动使用 `03_dependence/linux-x86_64/bin/` 下随附的 `minimap2` 2.31 与 `samtools` 1.12；报告 1–7 的验证平台 |
| macOS arm64（Apple Silicon） | 当前验证平台，见报告 8 | 随附的 Linux 二进制在此无法执行；请按上面第 1 步用 conda 安装 `minimap2`，或使用 `--aligner r` |

在 macOS arm64 上做一次完整本地验证：

```bash
conda activate nanoamp
make test             # testthat 单元测试
make check            # R CMD build + R CMD check
make cli              # sh 02_code/cli/nanoamp doctor
make functional-test  # 全部数据集 × 模式 A/B/C，输入按 01_data/manifest.tsv 解析
```

最近一次 macOS arm64 验证结果（R 4.5.3、Biostrings 2.78.0、pwalign 1.6.0、
DECIPHER 3.6.0、conda `minimap2` 2.31）：

| 检查 | 结果 |
|---|---|
| `R CMD INSTALL 02_code` | 成功 |
| `testthat` 单元测试 | 全部通过，无跳过 |
| `R CMD check --no-manual` | **Status: OK** |
| `nanoamp doctor` | 平台识别为 `macos-arm64`，R 包全 TRUE，minimap2/samtools 解析成功 |
| `run_functional_tests.R`（3 数据集 × 32 样本 × 模式 A/B/C） | **168/168 全部 ok** |

在可与 Linux x86_64 基线对比的指标上，跨平台结果一致：方案 A 与公司变异表
位置/等位基因完全一致的样本为 **22/23**（与 `work_report.1.md` 相同），方案 C
原始精确匹配占比中位数为 **12.0%**（同样相同）。

面向 Linux x86_64 的历史文档原样保留在 `00_materials/`（工作报告属于日志，不做
改写；本轮报告 8 列出了发生变化的路径），Linux 相关的依赖说明保留在
`02_code/inst/docs/INSTALL_DEPENDENCIES-CN.md`。英文版见 `README.md`。
