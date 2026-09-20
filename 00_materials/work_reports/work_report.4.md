# 工作报告 4：R-only 路线、依赖教程与 Windows GUI 初版

> 日期：2026-09-20
> 关联：`work_report.1.md`、`work_report.2.md`、`work_report.3.md`
> 本轮范围：取消 Python 版本、CLI 保持 R 实现、补依赖安装教程、开发 R Shiny Windows GUI

---

## 1. 摘要

根据最新计划，本轮做了四项调整和开发：

1. **取消 Python 版本**：删除 `02_code/python/` 占位，所有开发统一到 R 技术栈；
2. **CLI 保持基于 R**：新增 Windows `.bat` 启动脚本，CLI 仍由 `nanoamp` R 包提供；
3. **补齐依赖安装教程**：新增 Linux 和 Windows 下 `minimap2`、`samtools` 的安装与 PATH 配置文档；
4. **开始 Windows GUI 开发**：用 R Shiny 实现 GUI 初版，并提供 Windows 启动脚本、RInno 打包骨架和 Windows CI。

验证结果：

- `devtools::test("02_code/r")`：核心测试 + GUI 测试全部通过；
- `R CMD check --no-manual --no-build-vignettes`：**Status: OK**；
- GUI 无头启动：HTTP 200，页面标题正确；
- GUI 后端完整流程：`testServer()` 模拟“选择文件 → 运行 → 输出结果”，状态为 `Analysis complete`，5 个输出文件正确生成。

---

## 2. 路线调整：取消 Python 版本

### 2.1 删除的内容

```text
02_code/python/README.md
02_code/python/pyproject.toml
02_code/python/src/nanoamp/__init__.py
02_code/python/src/nanoamp/cli.py
02_code/python/tests/test_placeholder.py
```

### 2.2 文档同步调整

| 文件 | 调整 |
|---|---|
| `02_code/README.md` | 改为 R-only 结构，说明 GUI 使用 R Shiny |
| `02_code/README-CN.md` | 对应中文版本 |
| `02_code/cli/README.md` | 明确 CLI 由 R 包提供，Python CLI 已取消 |
| `02_code/gui/README.md` | 从 PySide6 方案改为 R Shiny 方案 |
| `02_code/shared/docs/output_schema.md` | 改为 R 核心库 / CLI / GUI 共用 schema |
| `04_results/README.md` | 去掉 python 结果目录 |

---

## 3. CLI：保持基于 R

CLI 逻辑仍集中在 `02_code/r/R/cli.R`，包内函数 `nanoamp_cli()` 提供：

```text
nanoamp call
nanoamp batch
nanoamp doctor
nanoamp help
```

本轮新增 Windows 启动脚本：

| 文件 | 用途 |
|---|---|
| `02_code/r/inst/scripts/nanoamp.bat` | Windows 下运行 CLI |
| `02_code/r/inst/scripts/nanoamp-gui.bat` | Windows 下启动 GUI |
| `02_code/r/inst/scripts/nanoamp-gui` | Linux / macOS 下启动 GUI |

Windows CLI 示例：

```bat
02_code\r\inst\scripts\nanoamp.bat call --reads sample.fastq --reference target.fa --outdir results\sampleA
```

---

## 4. 依赖安装教程

新增两份文档：

| 文件 | 语言 |
|---|---|
| `02_code/r/INSTALL_DEPENDENCIES.md` | 英文 |
| `02_code/r/INSTALL_DEPENDENCIES-CN.md` | 中文 |

覆盖内容：

1. `minimap2`、`samtools` 各自的作用；
2. Linux 下 conda / mamba 和 apt / dnf 两种安装方式；
3. Windows 下 conda / mamba（推荐）、预编译二进制和 WSL2 三种方式；
4. Windows `PATH` 配置步骤和示例路径；
5. RStudio 需要重启才能识别新的 `PATH`；
6. R 包依赖（必需 / 可选）的安装命令；
7. 用 `nanoamp doctor` 验证环境；
8. Windows 常见坑：conda 环境未激活、路径含空格或中文、多个 R 版本等；
9. 后续减少外部依赖的计划：Rsamtools 替代 samtools、R 内比对后端。

---

## 5. R Shiny GUI 初版

### 5.1 代码结构

| 文件 | 内容 |
|---|---|
| `02_code/r/R/gui.R` | `nanoamp_gui()`、`nanoamp_gui_app()`、UI、server、辅助函数 |
| `02_code/r/inst/shiny/app.R` | 独立 Shiny 入口，供 RInno / 外部启动器使用 |
| `02_code/r/tests/testthat/test-gui.R` | GUI 后端回归测试 |
| `02_code/r/inst/scripts/nanoamp-gui.bat` | Windows GUI 启动器 |
| `02_code/r/inst/scripts/nanoamp-gui` | Linux / macOS GUI 启动器 |

### 5.2 GUI 功能

- FASTQ 文件选择；
- 目的序列 FASTA 选择；
- 输出目录输入；
- 模式选择：A 参考引导 / B 从头聚类 / C 精确匹配；
- `top_n` 参数；
- 高级参数：`min_reads`、`min_freq`、`min_identity`、`identity_cutoff`、
  `min_cluster_reads`、`consensus_method`、`threads`、是否保留中间文件；
- 运行按钮、进度提示、状态提示；
- 日志窗口；
- 单倍型表格、变异表格、QC 表格；
- 下载 `haplotypes.tsv` 和 `variants.tsv`；
- 打开输出目录按钮。

### 5.3 启动方式

R 控制台：

```r
library(nanoamp)
nanoamp_gui()
```

只获取 app 对象、不启动服务器：

```r
app <- nanoamp_gui_app()
```

Windows：

```bat
Rscript -e "library(nanoamp); nanoamp_gui()"
:: 或
02_code\r\inst\scripts\nanoamp-gui.bat
```

### 5.4 GUI 依赖

GUI 依赖已加入 `Suggests`：

```text
shiny
DT
```

没有安装 DT 时，GUI 会自动退回 `shiny::tableOutput`。

---

## 6. Windows 打包与持续集成

### 6.1 RInno 打包骨架

新增：

```text
02_code/r/inst/windows/README.md
02_code/r/inst/windows/build_installer.R
```

目标是在 Windows 机器上用 RInno 把 R、`nanoamp`、依赖和 GUI 打包成一个安装包。
骨架包含：

- 运行 RInno 的前置条件；
- `create_app()` 示例；
- `compile_iss()` 后续步骤；
- 需要随包提供的 `minimap2.exe`、`samtools.exe` 说明。

注意：RInno 本身未安装，且 Windows 安装包必须在 Windows 上构建，本轮只完成骨架和文档。

### 6.2 Windows CI

新增 GitHub Actions：

```text
.github/workflows/R-CMD-check.yaml
```

在 `ubuntu-latest` 和 `windows-latest` 上运行：

```r
rcmdcheck::rcmdcheck("02_code/r", args = "--no-manual", error_on = "error")
```

CI 只安装硬依赖和 testthat；没有 `minimap2` / `samtools` 时，相关单元测试会自动跳过。

---

## 7. 验证结果

### 7.1 单元测试与 GUI 测试

```bash
Rscript -e 'devtools::test("02_code/r", reporter = "summary")'
```

结果：

- 核心测试：`cs` 解析、`apply_variants`、方案 A/B/C 合成数据、manifest；
- GUI 测试：`testServer()` 模拟 Mode C 完整流程；
- 全部通过，无 warning。

### 7.2 R CMD check

```bash
R CMD build 02_code/r
R CMD INSTALL nanoamp_0.1.0.tar.gz
R CMD check --no-manual --no-build-vignettes nanoamp_0.1.0.tar.gz
```

结果：

```text
Status: OK
```

### 7.3 GUI 无头验证

```bash
Rscript -e 'library(nanoamp); nanoamp_gui_app()'
# shiny.appobj

Rscript -e 'library(nanoamp); nanoamp_gui(launch.browser = FALSE, port = 8765, host = "127.0.0.1")'
# HTTP 200
# 页面标题: nanoamp - Nanopore Amplicon Haplotype Analysis
```

### 7.4 GUI 后端完整流程

用 `shiny::testServer()` 模拟：

1. 选择 E4-3 的 `reads.fastq`；
2. 选择 `reference.self.fa`；
3. 选择输出目录；
4. 模式 C；
5. 点击运行。

结果：

```text
Analysis complete. Output: .../04_results/r/gui_testServer
```

生成文件：

```text
haplotypes.tsv
haplotypes.fasta
variants.tsv
qc.tsv
run_manifest.json
```

GUI 测试使用 Mode C，因此不依赖 `minimap2` 和 `samtools`，可以在 CI 中稳定运行。

---

## 8. 当前限制

1. **GUI 同步执行**：点击运行后 Shiny 主线程被占用，长任务期间界面无响应；
   计划用 `callr::r_bg()` + `reactivePoll()` 改为后台执行并流式显示日志。
2. **输出目录选择**：当前是文本输入，尚未接入 `shinyFiles` 目录选择器。
3. **未构建 Windows 安装包**：RInno 骨架已就绪，但需要在 Windows 机器上实际构建和测试。
4. **外部依赖**：方案 A/B 仍需要 `minimap2` 和 `samtools`；
   计划用 `Rsamtools` 去掉 samtools，并增加 R 内比对后端。
5. **GUI 界面语言**：当前界面为英文；后续可增加中文界面或语言切换。
6. **GTF/CDS 注释**：尚未实现。

---

## 9. 下一步

1. GUI 改为 `callr::r_bg()` + `reactivePoll()` 后台执行，实时显示日志和进度；
2. 增加输出目录选择器和“打开结果文件”按钮；
3. 实现 `samtools` → `Rsamtools` 替换，减少一个外部依赖；
4. 增加 `aligner = "r"` 的 R 内比对后端；
5. 在 Windows 上用 RInno 构建安装包，并在干净 Windows 10/11 上测试；
6. 增加 GUI 的中文界面；
7. 继续推进 GTF / CDS 功能注释。

---

## 10. 复现命令

```bash
# 安装 R 包
R CMD INSTALL 02_code/r

# 环境检查
nanoamp doctor

# 单元测试 + GUI 测试
Rscript -e 'devtools::test("02_code/r", reporter = "summary")'

# R CMD check
R CMD build 02_code/r
R CMD check --no-manual --no-build-vignettes nanoamp_0.1.0.tar.gz

# 启动 GUI
Rscript -e 'library(nanoamp); nanoamp_gui()'

# Windows 启动 GUI
02_code\r\inst\scripts\nanoamp-gui.bat

# Windows 运行 CLI
02_code\r\inst\scripts\nanoamp.bat doctor
```

---

## 11. Git 提交

| 提交 | 说明 |
|---|---|
| `2922a4e` | feat: add R Shiny GUI, Windows launchers and dependency guides |

本报告提交后工作区应保持干净；GUI 测试输出位于 `04_results/r/`，按约定不进入 Git。
