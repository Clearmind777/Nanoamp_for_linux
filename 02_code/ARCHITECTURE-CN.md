# 02_code：源代码目录

`02_code/` 既是本仓库的代码根目录，也是 `nanoamp` R 包根目录：可以直接用
`R CMD INSTALL 02_code` 安装。除包文件外，这里还放命令行启动器、共享契约和
仓库级辅助脚本；这些非包内容通过 `.Rbuildignore` 排除在构建产物之外。

```text
02_code/
|-- DESCRIPTION / NAMESPACE / LICENSE / nanoamp.Rproj   # R 包根（已摊平）
|-- R/                      # nanoamp R 包源码
|-- tests/testthat/         # 单元测试
|-- man/                    # 生成的帮助文档
|-- exec/nanoamp            # 包内 CLI 包装（安装后为 <pkg>/exec/nanoamp）
|-- inst/
|   |-- docs/               # 依赖安装教程
|   `-- scripts/            # 随包发布的 CLI 入口与安装脚本
|-- cli/                    # 仓库级 CLI 入口与启动器
|-- shared/                 # 参数与输出契约
|   |-- params/default_params.json
|   `-- docs/output_schema.md
|-- scripts/                # 仓库级辅助脚本（不属于 R 包）
|   |-- prepare_test_data.R
|   |-- run_analysis.R
|   `-- run_functional_tests.R
|-- README.md / README-CN.md                # 包使用说明
`-- ARCHITECTURE.md / ARCHITECTURE-CN.md    # 本文件：目录结构与契约
```

为什么包不再多套一层目录：本仓库不是“纯 R 包”，而是一个“内含 R 包的命令行
发行版”。把 `DESCRIPTION` 和 `R/` 直接放在 `02_code/` 下，去掉多余的 `r/` 一层，
同时保留 `R CMD INSTALL 02_code` 这一条安装命令。

Python 版本与图形界面都不在本仓库范围内，本仓库只面向命令行版本开发。GUI 代码、
Shiny 界面与 Windows 安装器已在早前的修订中移除，只保留在姊妹仓库
`a_09_18_26_mapping_programs_dev_for_win`。外部工具统一放在仓库根目录的
`03_dependence/`。

## 设计原则

1. **一套算法，一个外壳**：CLI 调用 `nanoamp` R 包，不重复实现分析逻辑；
2. **共享契约**：参数名、默认值和输出列在 `shared/` 统一定义；
3. **数据与代码分离**：测试数据在 `01_data/`，运行结果在 `04_results/`；
4. **优先使用内置工具**：外部工具先从
   `03_dependence/<os>-<arch>/bin/` 解析，其次才是 `PATH`；
5. **不重复存数据**：`01_data/manifest.tsv` 只记录逻辑名到
   `01_data/test_data/` 真实文件的映射，不再复制或软链接。

## 快速开始

```bash
# 安装 R 包
R CMD INSTALL 02_code

# 环境检查（仓库内启动器）
sh 02_code/cli/nanoamp doctor

# 从 manifest 查一个样本的真实路径
Rscript -e 'm <- data.table::fread("01_data/manifest.tsv");
  print(m[dataset=="TSM20260826" & sample=="E4-3", .(role, path)])'

# 单样本分析
sh 02_code/cli/nanoamp call \
  --reads 01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq \
  --reference 01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.1.seq \
  --mode A --top-n 20 \
  --outdir 04_results/r/demo/E4-3
```

R 控制台：

```r
library(nanoamp)
res <- run_haplotype_analysis(
  reads     = "01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.fastq",
  reference = "01_data/test_data/TSM20260826-020-01254/E4-3_TSM20260826-020-01254_20260827-020-BAN05-5_H08.1.seq",
  outdir    = "04_results/r/demo/E4-3",
  mode      = "A"
)
res$haplotypes
```

## 当前状态

| 组件 | 状态 |
|---|---|
| R 包 | 已实现，并通过 `R CMD check`（`Status: OK`） |
| 基于 R 的 CLI | 已实现（`nanoamp_cli()` 和 `02_code/cli`） |

外部工具统一放在 `03_dependence/`；平台支持矩阵和 R 内后备方案见
`03_dependence/README-CN.md`。

## 共享契约

- `shared/params/default_params.json`：参数名与默认值；
- `shared/docs/output_schema.md`：输出文件与字段定义；
- `cli/README.md`：CLI 命令契约。
