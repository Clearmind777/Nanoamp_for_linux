# 工作报告 3：R 包封装、R 包教程与 CLI 版本

> 日期：2026-09-20
> 关联：`work_report.1.md`、`work_report.2.md`、`programs_dev_plan_1.md`
> 本轮范围：R 包封装与验证、R 包使用教程、中英文 README、基于 R 的 CLI

---

## 1. 摘要

本轮完成了五件事：

1. 把原先“脚本 + source()”形式的 R 代码封装成标准 R 包 `nanoamp`；
2. 通过 `R CMD build`、`R CMD INSTALL`、`R CMD check` 和功能回归验证包可用性；
3. 基于包内 API 实现了 CLI：`nanoamp call` / `batch` / `doctor`；
4. 撰写了完整的 R 包使用教程：`README.md`（英文）与 `README-CN.md`（中文）；
5. 重新跑了 168 次功能回归测试，确认封装后功能没有退化。

关键结果：

- `R CMD check --no-manual --no-build-vignettes`：**Status: OK**（0 warning，0 note）；
- 功能测试：168 次运行（3 模式 × 56 组），**0 次失败**；
- 方案 A 对公司变异召回率仍为 **163 / 167 = 97.6%**，22 / 23 个样本 100%；
- 方案 B（DECIPHER）召回率 **114 / 167 = 68.3%**；
- CLI `doctor`、`call` 均通过已安装包的验证。

---

## 2. R 包封装

### 2.1 包结构

```text
02_code/r/
├── DESCRIPTION
├── NAMESPACE                  # roxygen2 生成
├── LICENSE
├── .Rbuildignore
├── R/
│   ├── package.R              # 包级文档 + @import data.table
│   ├── utils.R                # 工具函数、version、默认参数
│   ├── io.R                   # FASTA / FASTQ / 公司变异表读写
│   ├── align.R                # minimap2 + samtools
│   ├── variants.R             # cs tag、候选变异、缺失区段归一化
│   ├── correct.R              # 方案 A
│   ├── cluster.R              # 方案 B（DECIPHER）
│   ├── exact.R                # 方案 C
│   ├── haplotypes.R           # 统一调度入口
│   ├── cli.R                  # nanoamp_cli()
│   ├── defaults.R             # nanoamp_defaults()
│   └── zzz.R                  # globalVariables
├── man/                       # roxygen2 生成的帮助文档
├── inst/
│   └── scripts/
│       ├── run_analysis.R
│       ├── nanoamp.R
│       ├── run_functional_tests.R
│       ├── prepare_test_data.R
│       └── install_cli.sh
├── exec/
│   └── nanoamp                # shell 包装
├── tests/
│   ├── testthat.R
│   └── testthat/test-core.R
├── README.md                  # 英文教程
├── README-CN.md               # 中文教程
└── nanoamp.Rproj
```

### 2.2 DESCRIPTION

- Package: `nanoamp`
- Version: `0.1.0`
- License: MIT
- Imports: `Biostrings`、`IRanges`、`Matrix`、`Rsamtools`、`ShortRead`、
  `data.table`、`jsonlite`、`optparse`、`readxl`、`methods`、`stats`、`utils`
- Suggests: `DECIPHER`、`testthat`
- Encoding: UTF-8

### 2.3 导出 API

| 函数 | 说明 |
|---|---|
| `run_haplotype_analysis()` | 主入口，支持 mode A/B/C |
| `nanoamp_defaults()` | 返回默认参数列表 |
| `nanoamp_version()` | 返回包版本 |
| `nanoamp_cli()` | CLI 入口，可由 `nanoamp` 可执行文件调用 |

方案 A/B/C 的内部函数保留在命名空间中，测试和开发脚本通过 `nanoamp:::` 调用。

### 2.4 重构要点

1. 删除 `R/load_all.R`：包加载时不再 source 文件；
2. 删除 `config/default_params.R`：默认参数统一到 `R/utils.R` 和
   `R/defaults.R`；
3. `scripts/`、`tools/`、开发测试脚本统一移入 `inst/scripts/`；
4. CLI 从独立脚本重构为包内 `nanoamp_cli()`；
5. 用 roxygen2 生成 `NAMESPACE` 和 `man/`；
6. 把 R/ 源码中的中文注释和字符串改为 ASCII（公司中文列名用 `\u` 转义），
   消除 `R CMD check` 的 non-ASCII warning；
7. 增加 `R/zzz.R` 的 `globalVariables()`，消除 data.table NSE 带来的 NOTE。

---

## 3. CLI 版本

### 3.1 包内实现

CLI 逻辑集中在 `R/cli.R`：

- `nanoamp_cli(args)`：解析第一个子命令，支持 `call`、`batch`、`doctor`、`help`；
- 所有分析都调用包内 `run_haplotype_analysis()`，不复制算法。

### 3.2 三种调用方式

**安装为系统命令：**

```bash
sh "$(Rscript --vanilla -e 'cat(system.file("scripts", "install_cli.sh", package = "nanoamp"))')" ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
nanoamp doctor
```

**通过包内 exec 包装：**

```bash
sh "$(Rscript --vanilla -e 'cat(system.file("exec", "nanoamp", package = "nanoamp"))')" doctor
```

**通过 Rscript 包装脚本：**

```bash
Rscript 02_code/r/inst/scripts/nanoamp.R doctor
```

### 3.3 命令示例

```bash
# 单样本
nanoamp call \
  --reads sample.fastq \
  --reference target.fa \
  --mode A \
  --top-n 20 \
  --outdir results/sampleA

# 多样本批处理
nanoamp batch \
  --sample-sheet samples.tsv \
  --mode A \
  --outdir results/batch

# 环境检查
nanoamp doctor
```

### 3.4 CLI 验证

实际执行了：

```bash
EXEC=$(Rscript --vanilla -e 'cat(system.file("exec","nanoamp",package="nanoamp"))')
sh "$EXEC" doctor
sh "$EXEC" call --reads ... --reference ... --mode C --outdir 04_results/r/cli_pkg_smoke
```

`doctor` 正确报告 DECIPHER、minimap2、samtools；`call` 正确生成
`haplotypes.tsv`、`haplotypes.fasta`、`variants.tsv`、`qc.tsv`、
`run_manifest.json`。

---

## 4. 使用教程与 README

### 4.1 R 包教程

| 文件 | 语言 | 内容 |
|---|---|---|
| `02_code/r/README.md` | 英文 | 安装、快速开始、三种模式、参数、输出、CLI、RStudio、测试数据、故障排查 |
| `02_code/r/README-CN.md` | 中文 | 与英文版一一对应的中文教程 |

教程覆盖：

1. 依赖安装和 R 包安装；
2. `run_haplotype_analysis()` 的最小示例；
3. 方案 A/B/C 的适用场景和限制；
4. 参数表与默认值；
5. 输出文件和字段解释；
6. CLI 的安装与使用；
7. RStudio 使用流程；
8. 测试数据的生成与运行示例；
9. 单元测试、功能测试和 `R CMD check`；
10. 常见问题排查表。

### 4.2 顶层代码目录 README

`02_code/README.md` 改为纯英文，`02_code/README-CN.md` 为对应中文版本，
说明多语言目录结构、共享契约、R 包快速开始和各组件状态。

---

## 5. 验证结果

### 5.1 构建与安装

```bash
R CMD build 02_code/r
R CMD INSTALL nanoamp_0.1.0.tar.gz
```

结果：

- 构建成功，生成 `nanoamp_0.1.0.tar.gz`；
- 安装成功，安装路径为当前 R 库；
- `library(nanoamp)` 正常；
- `nanoamp_version()` 返回 `0.1.0`；
- `nanoamp_defaults()` 返回 13 个默认参数。

### 5.2 R CMD check

```bash
R CMD check --no-manual --no-build-vignettes nanoamp_0.1.0.tar.gz
```

结果：

```text
Status: OK
```

无 warning、无 note，测试 `testthat.R` 通过。

### 5.3 环境检查

```bash
nanoamp doctor
```

关键依赖均可用：

```text
DECIPHER     TRUE
minimap2     /usr/bin/minimap2
samtools     /usr/local/bin/samtools
```

### 5.4 功能回归测试

```bash
Rscript 02_code/r/inst/scripts/run_functional_tests.R \
  --outdir 04_results/r/test_run_2 --modes A,B,C --threads 4
```

结果：168 次运行（每模式 56 次），0 次失败。

| 模式 | 运行数 | 成功 | top1 平均比例 | 公司变异平均重合率 | 平均耗时 |
|---|---:|---:|---:|---:|---:|
| A | 56 | 56 | 0.6748 | 0.9807 | 0.72 s |
| B | 56 | 56 | 0.7480 | 0.5642 | 5.02 s |
| C | 56 | 56 | 0.1231 | 0 | 0.09 s |

与公司结果对比（仅 self 参考）：

| 模式 | 命中 / 公司变异 | 召回率 | 100% 重合样本 |
|---|---:|---:|---:|
| A | 163 / 167 | 97.6% | 22 / 23 |
| B | 114 / 167 | 68.3% | 7 / 23 |

结论：封装为 R 包后，功能与封装前一致，方案 A 仍为主力方法。

---

## 6. 过程中发现并修复的问题

| 问题 | 现象 | 修复 |
|---|---|---|
| CLI 参数传递错误 | `exec/nanoamp doctor` 打印 usage | 去掉 `--args`，改为 `Rscript -e ... "$@"`；`nanoamp_cli()` 兼容前导 `--args` |
| 内部函数不可见 | 功能测试调用 `log_info()` 报错 | 开发脚本改用 `nanoamp:::log_info()`；`read_company_variants()` 同理 |
| non-ASCII 检查警告 | R CMD check 报 7 个 R 文件含非 ASCII | 注释和提示改为英文；公司中文列名改为 `\u` 转义 |
| `inst/exec` 警告 | R 不建议在 inst 下放 exec | 移动到顶层 `exec/nanoamp` |
| DECIPHER API 静态引用 | check 报 `Missing or unexported object: DECIPHER::IdClusters` | 改为 `getExportedValue()` 动态调用 |
| data.table NSE NOTE | 大量 no visible binding | 在 `R/zzz.R` 添加 `globalVariables()` |
| `flush.console` / `as` NOTE | 未声明 utils / methods | 改为 `utils::flush.console()`、`methods::as()`，并在 DESCRIPTION 增加 methods |

---

## 7. 路径变化

| 旧路径 | 新路径 |
|---|---|
| `02_code/r/R/load_all.R` | 已删除（由 R 包机制替代） |
| `02_code/r/config/default_params.R` | 已删除（合并到 `R/defaults.R` / `R/utils.R`） |
| `02_code/r/scripts/nanoamp.R` | `02_code/r/inst/scripts/nanoamp.R` |
| `02_code/r/scripts/run_analysis.R` | `02_code/r/inst/scripts/run_analysis.R` |
| `02_code/r/tools/prepare_test_data.R` | `02_code/r/inst/scripts/prepare_test_data.R` |
| `02_code/r/tests/run_functional_tests.R` | `02_code/r/inst/scripts/run_functional_tests.R` |
| 无 | `02_code/r/R/cli.R`、`R/defaults.R`、`R/package.R`、`R/zzz.R` |
| 无 | `02_code/r/exec/nanoamp`、`inst/scripts/install_cli.sh` |
| 无 | `02_code/r/DESCRIPTION`、`NAMESPACE`、`LICENSE`、`man/` |
| `02_code/r/README.md`（中文） | `02_code/r/README.md`（英文）+ `README-CN.md`（中文） |
| `02_code/README.md`（中文） | `02_code/README.md`（英文）+ `README-CN.md`（中文） |

---

## 8. 已知限制与下一步

1. **方案 B 仍受测序错误率限制**
   - 差异小于错误率的单倍型无法稳定分开；定量仍应使用方案 A；
   - 后续可加入“簇内变异检测”做两阶段分析。

2. **方案 A 的多单倍型参考策略**
   - 低比对率样本需要逐簇参考或统一参考；
   - 这是下一步算法改进的重点。

3. **CLI 的 Python 版本**
   - 当前 CLI 基于 R 包；
   - `02_code/python/` 和 `02_code/cli/README.md` 已定义好接口契约，
     可据此实现 Python 版本并保持输出一致。

4. **Windows GUI**
   - 目录和 CLI 已就绪；
   - 下一步可开始 PySide6 + PyInstaller 技术验证。

5. **功能注释**
   - GTF / CDS 注释尚未实现。

---

## 9. 复现命令

```bash
# 构建与安装 R 包
R CMD build 02_code/r
R CMD INSTALL nanoamp_0.1.0.tar.gz

# R CMD check（当前 Status: OK）
R CMD check --no-manual --no-build-vignettes nanoamp_0.1.0.tar.gz

# 环境检查
nanoamp doctor

# 单样本
nanoamp call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --top-n 20 \
  --outdir 04_results/r/demo/E4-3

# 完整功能测试
Rscript 02_code/r/inst/scripts/run_functional_tests.R \
  --outdir 04_results/r/test_run_2 --modes A,B,C --threads 4
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

---

## 10. Git 提交

| 提交 | 说明 |
|---|---|
| `69cf64b` | feat: package R core as nanoamp R package with CLI |

本报告提交后，工作区应保持干净；测试产物位于 `04_results/r/test_run_2/`，
按约定不进入 Git。
