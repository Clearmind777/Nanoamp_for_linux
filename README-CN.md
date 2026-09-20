# nanoamp

`nanoamp` 用于分析纳米孔 PCR 产物的测序数据。给定 FASTQ 和目的序列，它会校正
测序错误、重建单倍型，并输出数量最多、比例最高的序列。

## 仓库结构

```text
00_materials/     委托文档、开发方案和工作报告
01_data/          原始测试数据和规范化软链接层
02_code/          源代码
  r/              nanoamp R 包
  cli/            独立 R CLI 入口和启动器
  gui/            独立 R Shiny GUI 入口和启动器
  shared/         跨语言参数与输出契约
03_dependence/    随项目分发的外部工具与获取说明
04_results/       运行结果（除 README 外 Git 忽略）
05_builds/        R 构建包和 R CMD check 产物（Git 忽略）
tmp/              临时目录（Git 忽略）
```

## 快速开始

```bash
# 1. 安装 R 包
R CMD INSTALL 02_code/r

# 2. 环境检查（仓库内启动器）
sh 02_code/cli/nanoamp doctor

# 可选：安装全局 `nanoamp` 命令
sh 02_code/cli/install_cli.sh ~/.local/bin

# 3. 单样本分析
sh 02_code/cli/nanoamp call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --top-n 20 \
  --outdir 04_results/cli/demo

# 4. 启动 GUI
Rscript 02_code/gui/run_gui.R
```

R 控制台：

```r
library(nanoamp)
res <- run_haplotype_analysis(
  reads     = "01_data/ln_test_data/TSM20260826/E4-3/reads.fastq",
  reference = "01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa",
  outdir    = "04_results/r/demo/E4-3",
  mode      = "A"
)
res$haplotypes
```

## 文档索引

| 文档 | 内容 |
|---|---|
| `02_code/README.md` | 源码目录与组件状态 |
| `02_code/r/README.md` | R 包教程（英文） |
| `02_code/r/README-CN.md` | R 包教程（中文） |
| `02_code/r/inst/docs/INSTALL_DEPENDENCIES-CN.md` | Linux/Windows 下 minimap2、samtools 安装 |
| `02_code/cli/README.md` | CLI 契约与启动器 |
| `02_code/gui/README.md` | GUI 功能与 Windows 打包 |
| `03_dependence/README-CN.md` | 内置工具与平台支持矩阵 |
| `00_materials/README.md` | 规划文档与工作报告索引 |

## 外部工具

解析顺序：

1. `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`；
2. `03_dependence/<os>-<arch>/bin/`；
3. `PATH`。

仓库已内置 Linux x86_64 的 minimap2 2.31。没有官方 minimap2 二进制的平台
（Windows、ARM）可以使用 R 内后端：

```r
run_haplotype_analysis(..., aligner = "r")
```

samtools 不是必需依赖：默认用 `Rsamtools::asBam()` 完成 SAM→BAM。

## 常用命令

```bash
make install     # 安装 R 包
make test        # 运行 testthat 测试
make check       # 构建并 R CMD check
make cli         # 运行 nanoamp doctor
make gui         # 启动 Shiny GUI
make deps        # 获取外部工具
```

## 许可证

MIT。
