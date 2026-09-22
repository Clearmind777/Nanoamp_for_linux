# 工作报告 8：目录瘦身与 macOS arm64 验证

> 日期：2026-09-22
> 关联：`work_report.7.md`
> 本轮范围：
> 1. 删除 `01_data/ln_test_data` 冗余软链接层，改用 `01_data/manifest.tsv` 保存
>    “逻辑名 → 真实文件”映射，并同步修改全部代码路径；
> 2. 确认并固化“无 GUI、只有 CLI”的形态，把 `02_code/` 摊平为“包根目录 + 仓库级
>    目录”的结构；
> 3. 在一台 **macOS arm64（Apple Silicon）** 笔记本上完成本地验证（此前开发平台
>    是 Linux x86_64）；
> 4. 同步更新各级 README；
> 5. 提交并推送远端。

---

## 1. 删除 ln_test_data 软链接层

### 1.1 删除前的核实

`01_data/ln_test_data/` 是第 4 轮引入的“规范化软链接层”，用短名指向
`01_data/test_data/` 里的公司原始文件。删除前逐条核对：

| 检查项 | 结果 |
|---|---|
| manifest 记录条目 | 201 条 |
| 链接文件与目标文件逐字节 `cmp` | **201/201 完全一致，0 处差异** |
| 指向的物理文件数 | 145 个（部分角色共用同一文件，如 `reference.self` 与 `consensus.1` 同为 `*.1.seq`） |
| 目标文件缺失数 | 0 |

结论：该层不承载任何独有信息，删除不丢数据。

另外发现：本机的 `ln_test_data` 在 `git status` 中显示为 201 个 `T`（typechange）——
索引里是 `120000` 符号链接，工作区被检出成了普通文件。这也说明该层在
Windows 上曾被当作普通文件副本，其“链接”语义本身并不可靠。

### 1.2 新的做法

```text
01_data/
|-- test_data/      # 公司原始交付，永不修改
`-- manifest.tsv    # 逻辑名 -> 真实文件
```

`manifest.tsv` 列：`dataset`、`sample`、`role`、`cluster`、`path`、`source_note`，
其中 `path` 相对 `01_data/`。相比旧的 `link_path`/`target_path` 两列，去掉了恒等于
同一值的冗余列。

新旧映射经脚本逐条比对：**201 行完全相同，`source_note` 也完全相同**。

### 1.3 同步修改的代码与文档

| 位置 | 改动 |
|---|---|
| `02_code/scripts/prepare_test_data.R` | 重写：只生成 `01_data/manifest.tsv`，不再创建软链接，不再写每样本 `meta.tsv`；原始目录只读 |
| `02_code/scripts/run_functional_tests.R` | 从 `01_data/manifest.tsv` 读映射，按 `01_data/<path>` 解析输入 |
| `02_code/scripts/run_analysis.R` | `CONFIG` 改为 `test_data/` 真实路径 |
| `02_code/tests/testthat/test-core.R` | 测试改为断言 manifest 每个 `path` 都存在，且都以 `test_data/` 开头 |
| `01_data/README.md`、各级 README | 重写相关章节 |

用新脚本重新生成 manifest，与转换得到的版本 `diff` **完全一致**，说明生成逻辑可复现。

**收益**：仓库内每份数据只剩一份，磁盘占用减少约 41 MB；`01_data` 从 121 MB 降到 80 MB。

---

## 2. 收敛为纯 CLI 形态并摊平 02_code

### 2.1 关于 GUI

GUI 代码（`02_code/gui/`、`R/gui.R`、`inst/shiny/app.R`、`nanoamp-gui` 启动器、
GUI 文档与测试、`Makefile` 的 `gui` 目标）已在 `work_report.7.md` 那一轮
（提交 `7d5e58f`）随离线运行时一并删除。

本轮做的是**核实与固化**，而不是再次删除：

| 检查 | 结果 |
|---|---|
| 路径名含 `gui`/`shiny` 的受版本控制文件 | 0 |
| 内容含 `shiny`/`nanoamp_gui` 的受版本控制文件（`00_materials/` 历史报告除外） | 0 |
| Windows 相关文件（`.bat`/`.ps1`/`windows-*`） | 0 |
| `DESCRIPTION` 的 `Suggests` 中 `shiny`、`DT` | 已不在 |
| `NAMESPACE` 中 `nanoamp_gui*` 导出 | 已不在 |

结论：Linux / macOS 侧只有 CLI 形态，GUI 只存在于姊妹仓库
`a_09_18_26_mapping_programs_dev_for_win`。

### 2.2 02_code 摊平

原结构把 R 包埋在 `02_code/r/` 下，而仓库本身并不是“纯 R 包”，多出的这一层只是
历史遗留。本轮按“包根目录 + 仓库级目录”重排：

```text
02_code/
|-- DESCRIPTION / NAMESPACE / LICENSE / nanoamp.Rproj   # R 包根（上移一层）
|-- R/  man/  tests/  exec/  inst/                      # R 包标准内容
|-- cli/          # 仓库级 CLI 入口与启动器
|-- shared/       # 参数与输出契约
|-- scripts/      # 仓库级辅助脚本（不属于 R 包）
|-- README.md / README-CN.md                # 包使用说明
`-- ARCHITECTURE.md / ARCHITECTURE-CN.md    # 目录结构与契约（本文件原来占用 README 名）
```

两处命名冲突的处理：`02_code/README.md` 原先是“目录结构说明”，而
`02_code/r/README.md` 是“包使用说明”。摊平后把前者改名为 `ARCHITECTURE.md`
（中文同名 `-CN`），把后者保留为 `README.md`，两份内容都不丢。

`inst/scripts/` 里的 3 个脚本（`prepare_test_data.R`、`run_analysis.R`、
`run_functional_tests.R`）是仓库级工具，不是包运行所需，移到 `02_code/scripts/`；
包仍需随包发布的 `nanoamp.R` 与 `install_cli.sh` 留在 `inst/scripts/`。
`.Rbuildignore` 增加 `^cli$`、`^shared$`、`^scripts$`、`^ARCHITECTURE(-CN)?\.md$`，
构建产物经核对**只含包内容**。

同步修改：`Makefile`（`R_PKG := 02_code`）、`.github/workflows/R-CMD-check.yaml`
（检查路径 `02_code`）、`02_code/cli/nanoamp.R`（改为按 `DESCRIPTION`+`R/` 定位包根，
不再硬编码 `02_code/r`）、`DESCRIPTION` 的 `Suggests` 增加 `pwalign`、`pkgload`。

---

## 3. macOS arm64 本地验证

### 3.1 验证环境

本机为 macOS（Darwin 24.6.0）**arm64**。仓库随附的
`03_dependence/linux-x86_64/bin/{minimap2,samtools}` 是 Linux ELF，在此无法执行
（`cannot execute binary file`），因此按 README 的 conda 流程建立独立环境：

```bash
mamba create -y -p ./tmp/nanoamp-env -c conda-forge -c bioconda \
  r-base minimap2 samtools \
  r-data.table r-optparse r-jsonlite r-readxl \
  bioconductor-biostrings bioconductor-rsamtools bioconductor-shortread \
  bioconductor-iranges bioconductor-decipher \
  r-testthat r-pkgload
```

实际得到：R 4.5.3、minimap2 2.31-r1302（自带 `--cs`，方案 A/B 必需）、
samtools 1.24、Biostrings 2.78.0、pwalign 1.6.0、DECIPHER 3.6.0。
环境位于 `tmp/`，不进版本控制。

### 3.2 验证中发现并修复的问题

**问题：方案 B 在本机全部报错。**

```text
pairwiseAlignment() has moved from Biostrings to the pwalign package,
and is formally defunct in Biostrings >= 2.77.1.
```

根因在 `R/zzz.R` 的兼容层。它用

```r
if ("pairwiseAlignment" %in% getNamespaceExports("Biostrings")) ...
```

来判断提供者。但 Biostrings 有**三代**行为：

1. `< 2.77`：`pairwiseAlignment` 在 Biostrings 里且可用；
2. 过渡期：符号不再导出（旧的报错“not an exported object”）；
3. `>= 2.77.1`（本机）：符号**仍然导出**，但已是 defunct 桩函数，调用即中止。

旧判断在第 3 代上会把 defunct 桩函数当成可用实现选中，于是方案 B 必然失败。

修复：改为**优先使用 pwalign**（若已安装），仅在 pwalign 缺失时才回退 Biostrings，
并在回退前校验全部 5 个函数都真正导出。pwalign 与 Biostrings 的这 5 个函数签名、
返回值一致，已实测确认。同时在 `qc.tsv` 中新增 `pairwise_provider` 指标，记录实际
使用的包，便于今后排查。

这是一个**跨版本兼容性缺陷**，不只是 arm64 问题：任何装了 Biostrings ≥ 2.77.1 的
机器（包括 Linux x86_64）都会踩到，只是因为旧环境恰好停留在更早的 Bioconductor。

**顺带修复的两处**：

- `test-core.R` 用 `test_path("..","..","..","..")` 定位仓库根，在
  `pkgload + test_dir` 与 `devtools::test` 两种运行方式下工作目录不同，会算错路径
  并静默跳过 manifest 测试。改为向上逐级查找含 `01_data` 的目录。
- `Makefile` 的 `test` 目标依赖未在 `DESCRIPTION` 中声明的 `devtools`；改为
  `pkgload::load_all + testthat::test_dir`，与仓库 CLI 启动器使用的机制一致。

### 3.3 验证结果

| 检查 | 命令 | 结果 |
|---|---|---|
| 包安装 | `R CMD INSTALL 02_code` | 成功（新摊平结构下直接可用） |
| 单元测试 | `pkgload::load_all` + `testthat::test_dir` | **全部通过，无跳过** |
| 构建 + 检查 | `R CMD build` + `R CMD check --no-manual` | **Status: OK**（0 error / 0 warning / 0 note） |
| CLI | `sh 02_code/cli/nanoamp doctor` | 平台识别为 `macos-arm64`，10 个 R 包全 TRUE，minimap2/samtools 从 PATH 解析成功 |
| 包内 CLI | `sh 02_code/exec/nanoamp doctor` | 同样正常 |
| 功能测试 | `run_functional_tests.R --modes A,B,C` | **168/168 全部 ok，0 error** |
| manifest 可复现 | 重跑 `prepare_test_data.R` 后 `diff` | 与现状**完全一致** |

功能测试规模：3 个数据集（`TSM20260826`、`ZNF8`、`nano_seq`）× 32 个样本 ×
3 种模式 ×（self / wt 参考，方案 C 亦按参考跑通）= 168 次运行。

| 模式 | 运行数 | 成功 | 平均 top1 占比 | 与公司变异表平均重合率 | 平均耗时 |
|---|---:|---:|---:|---:|---:|
| A | 56 | 56 | 0.6750 | **0.9807** | 0.22 s |
| B | 56 | 56 | 0.7253 | 0.5409 | 1.06 s |
| C | 56 | 56 | 0.1231 | 0 | 0.11 s |

### 3.4 与 Linux x86_64 基线的一致性

这是本轮最关键的结论：**换平台不改变结果**。

| 指标 | `work_report.1.md`（Linux x86_64，23 样本） | 本轮（macOS arm64，本数据集全量） |
|---|---|---|
| 方案 A 频率 ≥5% 变异重合：位置与等位基因 100% 一致的样本 | **22 / 23** | **22 / 23** |
| 方案 C 原始精确匹配占比中位数 | **12.0%** | **12.0%** |

方案 A 的 22/23 与方案 C 的 12.0% 中位数两项独立指标都与 Linux 基线完全相同，
说明摊平目录、去掉软链接层、换用 pwalign 都没有改变分析行为。方案 C 的低占比也
再次印证“不能直接对原始 reads 做精确计数”这一设计前提。

---

## 4. README 更新

| 文件 | 改动 |
|---|---|
| `README.md` / `README-CN.md` | 安装命令改为 `R CMD INSTALL 02_code`；补“仓库结构”“开发平台”两节，含 Linux x86_64 与 macOS arm64 的平台矩阵、`make test/check/cli/functional-test` 验证流程；说明历史 Linux 文档原样保留在 `00_materials/` |
| `02_code/README.md` / `-CN.md` | 安装路径、RStudio 流程、测试数据章节、功能测试命令全部改为新路径；测试数据章节改为讲 manifest |
| `02_code/ARCHITECTURE.md` / `-CN.md` | 重画目录树（摊平后），解释“为什么包不再多套一层”“为什么不重复存数据”，补 GUI 已移除的说明 |
| `01_data/README.md` | 改写为 `test_data/` + `manifest.tsv` 两节，给出 awk / R 两种查表方式，说明旧软链接层已删除 |
| `02_code/inst/docs/INSTALL_DEPENDENCIES{,-CN}.md` | 新增 “2b. macOS（Intel 与 Apple Silicon）” 小节：conda 命令、Apple Silicon 注意事项、`pwalign` 必要性；补本地验证环境与可选 `pwalign` |

历史材料处理原则：`00_materials/` 下的委托、方案与 1–7 号工作报告**原样保留**，
不因本轮结构变化而改写（本轮新增本报告 8）。

---

## 5. 提交与推送

本轮改动量级：

```text
274 files changed, 798 insertions(+), 1434 deletions(-)
（其中 234 个文件删除来自 ln_test_data 层）
```

推送目标：`origin` = `git@github.com:Clearmind777/Nanoamp_for_linux.git`，分支 `main`。

---

## 6. 现状与已知限制

仓库现在是：

```text
README.md / README-CN.md   程序介绍 + conda 安装 + 平台矩阵
00_materials/              委托、方案、工作报告（1-7 为历史原文，8 为本轮）
01_data/                   test_data/ 原始交付 + manifest.tsv 名字映射（无冗余副本）
02_code/                   R 包根 + cli/ + shared/ + scripts/
03_dependence/             随附 Linux x86_64 minimap2 / samtools（macOS 用 conda）
04_results/                运行结果（含 test_run_macos_arm64/）
05_builds/                 R CMD build / check 产物
```

已知限制（本轮未处理，供后续决策）：

1. **方案 B 的 DECIPHER 距离矩阵警告**：`DECIPHER::DistanceMatrix()` 对
   `cluster_sequences()` 直接传入的未比对序列会警告 “N different sequence
   lengths. Using shorter length in each comparison.”。当前行为是既定实现的既有
   表现，非本轮引入；DECIPHER 官方更推荐的路径是先 `AlignSeqs()` 再算距离，改动
   会改变数值结果，因此本轮未动。警告已确认不影响运行结果。
2. **方案 B 的样本量上限**：`DistanceMatrix` 为 O(n²) 稠密矩阵，大样本（上万 reads）
   会有内存压力；`max_msa_seqs` 只约束共识用的 MSA 子集，不约束距离矩阵。
3. **`make check` 在本机需额外依赖**：`R CMD check` 的 tests 环节需要
   `pkgload`/`testthat`，已写入 `Suggests` 与 conda 安装清单。
4. `04_results/r/` 下的旧运行（`test_run_3` 等）为 Linux 时期产物，按约定保留。
