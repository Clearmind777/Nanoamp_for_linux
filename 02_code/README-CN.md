# 02_code：源代码目录

本目录包含 `nanoamp` R 包和基于 R 的命令行版本。本 Linux 仓库只提供命令行版本。

```text
02_code/
|-- README.md / README-CN.md
|-- shared/                 # 参数与输出契约
|   |-- params/default_params.json
|   `-- docs/output_schema.md
|-- r/                      # nanoamp R 包
|   |-- DESCRIPTION / NAMESPACE / LICENSE
|   |-- R/
|   |-- inst/
|   |   |-- docs/           # 依赖安装教程
|   |   `-- scripts/        # run_analysis.R、CLI、测试脚本
|   |-- tests/testthat/
|   |-- exec/nanoamp        # 包内 CLI 包装
|   |-- man/                # 生成的帮助文档
|   `-- README.md / README-CN.md
`-- cli/                    # 仓库级 CLI 入口与启动器
```

Python 版本与图形界面都不在本仓库范围内，本仓库只面向 Linux 命令行版本开发。
外部工具统一放在仓库根目录的 `03_dependence/`。

## 设计原则

1. **一套算法，一个外壳**：CLI 调用 `nanoamp` R 包，不重复实现分析逻辑；
2. **共享契约**：参数名、默认值和输出列在 `shared/` 统一定义；
3. **数据与代码分离**：测试数据在 `01_data/`，运行结果在 `04_results/`；
4. **优先使用内置工具**：外部工具先从
   `03_dependence/<os>-<arch>/bin/` 解析，其次才是 `PATH`。

## 快速开始

```bash
# 安装 R 包
R CMD INSTALL 02_code/r

# 环境检查（仓库内启动器）
sh 02_code/cli/nanoamp doctor

# 单样本分析
sh 02_code/cli/nanoamp call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --top-n 20 \
  --outdir 04_results/r/demo/E4-3
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
