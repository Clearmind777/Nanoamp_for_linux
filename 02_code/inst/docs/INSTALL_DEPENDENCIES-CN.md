# nanoamp 依赖安装与配置

nanoamp 只需要两样东西：下面的 **R 包**，以及一个**比对程序**。比对程序
（`minimap2`）已经为所有支持的平台预置在仓库里，所以正常情况下它不需要安装。

## 1. 需要哪些依赖

| 依赖 | 类型 | 用途 | 获取方式 |
|---|---|---|---|
| R 包 | R 包 | 核心分析 | `pak` / `install.packages()` / `BiocManager::install()`，见第 3 节 |
| `minimap2` | 外部命令 | 方案 A/B 的 reads 比对 | **已预置**在 `03_dependence/<os>-<arch>/bin/` |
| `DECIPHER` | 可选 R 包 | 方案 B 聚类与共识 | 见第 3 节 |
| `pwalign` | 可选 R 包 | Bioconductor ≥ 3.19 下的 `pairwiseAlignment()` | 见第 3 节 |
| `samtools` | 可选外部命令 | 仅当显式设置 `use_samtools = TRUE` | 不预置也不需要：`Rsamtools::asBam()` 负责 SAM→BAM |

方案 C（原始精确匹配）完全不需要 `minimap2`。`samtools` 从来不是必需依赖，因为
`Rsamtools::asBam()` 已经完成 SAM→BAM 转换——这也是它不再被预置的原因。

## 1.1 内置工具与 R 内后备

`nanoamp` 查找工具的顺序：

1. 环境变量 `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`；
2. `03_dependence/<os>-<arch>/bin/`；
3. `PATH`。

仓库为**四个支持的平台全部预置了 minimap2 2.31**：

| 平台 | 预置文件 | 已核实的运行时要求 |
|---|---|---|
| linux-x86_64 | `03_dependence/linux-x86_64/bin/minimap2` | glibc >= 2.14，系统 zlib |
| linux-arm64 | `03_dependence/linux-arm64/bin/minimap2` | glibc >= 2.17，系统 zlib |
| macos-x86_64 | `03_dependence/macos-x86_64/bin/minimap2` | 仅需 macOS 系统库 |
| macos-arm64 | `03_dependence/macos-arm64/bin/minimap2` | 仅需 macOS 系统库 |

由于这些二进制只链接操作系统自带的库，**刚克隆下来即可使用，不需要 conda、不需要
包管理器、也不需要联网**。版本、来源与 sha256 见 `03_dependence/manifest.tsv`；
为什么取自 conda-forge 见 `03_dependence/README-CN.md`。Windows 依赖材料由姊妹仓库
`a_09_18_26_mapping_programs_dev_for_win` 维护。

如果宿主与任何预置文件都不匹配（例如 glibc 过旧），不必安装任何东西，改用 R 内后端：

```r
run_haplotype_analysis(..., aligner = "r")
```

`samtools` 仍作为后备保留：如果它在 `PATH` 里，`use_samtools = TRUE` 就会用它
替代 `Rsamtools`。

## 2. 安装 minimap2（通常不需要）

只有当 `sh 02_code/cli/nanoamp doctor` 报告 `minimap2 NOT FOUND` 时才需要看这一节；
这只可能发生在上述四个平台之外，或预置文件丢失的情况下。

在任何有 `mamba`/`conda` 的机器上恢复预置二进制（跨平台下载在任何宿主上都可行，
不需要模拟器或 Docker）：

```bash
bash 03_dependence/fetch_dependencies.sh              # 当前平台
bash 03_dependence/fetch_dependencies.sh --all         # 四个平台全刷
```

若想用其他方式安装 minimap2（conda、Homebrew、apt 或自行编译），只要确保它在
`PATH` 上即可；nanoamp 会在预置查找失败后回退到 `PATH`。

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
BiocManager::install("DECIPHER")             # 方案 B 聚类与共识
BiocManager::install("pwalign")              # pairwiseAlignment() 提供者，供
                                             # aligner = "r" 和 Bioconductor
                                             # >= 3.19 下的方案 B 标注使用；
                                             # 惰性解析，只用 minimap2 不需安装
```

### 自动安装（pak 优先）

`02_code/scripts/install_r_deps.R` 会安装上面全部内容。它优先调用 `pak::pak()`：
pak 会一次性解析 CRAN 与 Bioconductor 的依赖图，并优先使用 CRAN / Bioconductor
发布的**预编译二进制**（macOS arm64、macOS x86_64 与 Windows 都有），可以避免长时间
源码编译。若 pak 缺失或失败，则回退到 `install.packages()` + `BiocManager::install()`。

```bash
Rscript 02_code/scripts/install_r_deps.R              # 必需 + 可选
Rscript 02_code/scripts/install_r_deps.R --dry-run    # 只报告缺哪些
Rscript 02_code/scripts/install_r_deps.R --only-required
```

### 手动等价做法

如果你更愿意自己执行，下面两条命令就是回退路径所做的事：

```r
install.packages(c("data.table", "jsonlite", "optparse", "readxl"))
BiocManager::install(c("Biostrings", "IRanges", "Rsamtools", "ShortRead",
                       "DECIPHER", "pwalign"))
```

本仓库本地验证所用的安装位置（一次性的，`tmp/` 已被 Git 忽略）：

```bash
mamba create -y -p ./tmp/nanoamp-env -c conda-forge -c bioconda \
  r-base \
  r-data.table r-optparse r-jsonlite r-readxl \
  bioconductor-biostrings bioconductor-rsamtools bioconductor-shortread \
  bioconductor-iranges bioconductor-decipher \
  r-testthat r-pkgload
```

注意这份清单里**故意没有 minimap2**：直接用 `03_dependence/` 里的预置二进制。

## 4. 验证清单

```r
library(nanoamp)
nanoamp_cli("doctor")
```

期望输出——注意 `minimap2` 解析到的是**仓库内部**的路径，`samtools` 被标注为可选：

```text
nanoamp version: 0.1.0
R version: ...
Rscript: ...
platform: macos-arm64
dependence directory: /path/to/repo/03_dependence
  Biostrings   TRUE
  ...
  DECIPHER     TRUE
  minimap2     /path/to/repo/03_dependence/macos-arm64/bin/minimap2 (2.31-r1302)
  samtools     NOT FOUND (optional; Rsamtools is used by default)
```

需要确认：

- `minimap2` 显示路径而不是 `NOT FOUND`；
- `samtools` 是可选的，除非 `use_samtools = TRUE`，否则显示 `NOT FOUND` 也没关系；
- R 包显示 `TRUE`；
- `DECIPHER` 可以是 `FALSE`：方案 B 会自动降级，但建议安装。

## 5. 依赖缩减现状

以下改进已经实现：

1. `minimap2` 已为四个平台（linux/macos × x86_64/arm64）全部预置，且只链接操作系统
   自带的库，因此运行时不需要 conda、包管理器或联网；
2. 默认用 `Rsamtools::asBam()` 完成 SAM→BAM，`samtools` 命令不再预置、变成可选；
3. `aligner = "r"` 提供 R 内成对比对后端，适合中小数据，也适合预置二进制与宿主不
   匹配的情况（例如 glibc 低于 2.14）；
4. `minimap2` 仍然是大数据量下的推荐后端。

只有显式设置 `use_samtools = TRUE` 时才需要 samtools。
