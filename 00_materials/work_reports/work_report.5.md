# 工作报告 5：CLI/GUI 入口补全、依赖分发与跨平台兼容

> 日期：2026-09-20
> 关联：`work_report.3.md`、`work_report.4.md`
> 本轮范围：补全 `02_code/cli`、`02_code/gui`，建立 `03_dependence/`，改进跨平台兼容

---

## 1. 摘要

本轮针对四个问题做了集中修复：

1. `02_code/cli` 不再是空目录：增加了可独立运行的 CLI 入口和 Linux/Windows 启动器；
2. `02_code/gui` 不再是空目录：增加了可独立运行的 Shiny 入口和启动器；
3. 建立 `03_dependence/`，内置 Linux x86_64 的 minimap2 2.31 和 samtools 1.12，并让程序优先只调用这里解析到的工具；
4. 改进跨平台兼容：samtools 用 Rsamtools 替代，Windows/ARM 无官方二进制时使用纯 R 比对后端。

验证结果：

- `devtools::test("02_code/r")`：core + dependence + gui 测试全部通过；
- `R CMD check --no-manual`：**Status: OK**；
- 独立 CLI `nanoamp doctor` 正确显示 `03_dependence` 中的工具路径和版本；
- 完整功能测试 168/168 成功，方案 A 仍为 **163/167 = 97.6%**，22/23 个样本 100% 重合。

---

## 2. `02_code/cli` 补全

新增文件：

```text
02_code/cli/
|-- nanoamp.R          # 独立 Rscript CLI 入口
|-- nanoamp            # Linux / macOS 启动器
|-- nanoamp.bat        # Windows 启动器
|-- install_cli.sh     # Linux / macOS 安装到 PATH
|-- install_cli.bat    # Windows 安装 nanoamp.cmd
`-- README.md
```

入口逻辑：

1. 在仓库内运行时，优先用 `pkgload::load_all("02_code/r")` 加载源码包，保证使用最新代码；
2. 不在仓库内时，使用已安装的 `nanoamp` R 包；
3. 最终调用包内 `nanoamp_cli()`。

验证：

```bash
sh 02_code/cli/nanoamp doctor
Rscript 02_code/cli/nanoamp.R call --reads ... --reference ... --mode A --outdir ...
```

---

## 3. `02_code/gui` 补全

新增文件：

```text
02_code/gui/
|-- app.R             # 独立 Shiny app（可由 shiny::runApp 加载）
|-- run_gui.R         # 启动脚本
|-- nanoamp-gui       # Linux / macOS 启动器
|-- nanoamp-gui.bat   # Windows 启动器
`-- README.md
```

`app.R` 使用 `nanoamp` 包内部的 UI / server，并同样支持源码包优先加载。

验证：

```bash
Rscript -e 'shiny::runApp("02_code/gui", host="127.0.0.1", port=8766, launch.browser=FALSE)'
```

结果：HTTP 200，页面正常渲染。

---

## 4. `03_dependence` 依赖分发

### 4.1 目录结构

```text
03_dependence/
|-- README.md / README-CN.md
|-- manifest.tsv
|-- fetch_dependencies.sh
|-- licenses/minimap2-LICENSE.txt
|-- linux-x86_64/bin/minimap2
|-- linux-x86_64/bin/samtools
|-- linux-arm64/README.md
|-- windows-x86_64/README.md
|-- windows-arm64/README.md
|-- macos-x86_64/README.md
`-- macos-arm64/README.md
```

### 4.2 已内置的二进制

| 平台 | 工具 | 版本 | 来源 |
|---|---|---|---|
| linux-x86_64 | minimap2 | 2.31-r1302 | 官方 GitHub release 预编译包 |
| linux-x86_64 | samtools | 1.12 | 从本服务器 `/usr/local/bin/samtools` 拷贝 |

大小约 9.7 MB。

### 4.3 工具解析顺序

`nanoamp_tool_path()` 按以下顺序解析：

1. 环境变量 `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`；
2. `03_dependence/<os>-<arch>/bin/<tool>`；
3. `PATH`。

`NANOAMP_DEPENDENCE_DIR` 可以覆盖 `03_dependence` 的位置。

`nanoamp doctor` 现在会输出：

```text
platform: linux-x86_64
dependence directory: .../03_dependence
minimap2     .../03_dependence/linux-x86_64/bin/minimap2 (2.31-r1302)
samtools     .../03_dependence/linux-x86_64/bin/samtools (samtools 1.12)
```

### 4.4 平台现实情况

调查结论：

- minimap2 官方只发布 Linux x86_64 预编译包；
- samtools 官方不提供 Windows 二进制；
- conda-forge / bioconda 不提供 Windows 版 samtools / minimap2；
- conda-forge / bioconda 提供 Linux ARM64 的 samtools。

因此：

- Linux x86_64：直接使用内置二进制；
- Linux ARM64 / macOS：通过 `fetch_dependencies.sh` 中的 conda 命令获取；
- Windows x86_64 / ARM64：没有官方二进制，使用 R 内后端 `aligner = "r"` 或 WSL2。

---

## 5. 跨平台兼容性改造

### 5.1 samtools 不再必需

原来的流程是：

```text
minimap2 | samtools sort
```

现在改为：

```text
minimap2 -> SAM 文件 -> Rsamtools::asBam() -> BAM + BAI -> scanBam()
```

优点：

- 不再依赖 samtools 命令；
- 避免 Windows 上没有 samtools 的问题；
- 避免 shell 管道在不同平台上的引号和转义差异。

如果显式设置 `use_samtools = TRUE`，仍然会走内置 samtools。

### 5.2 新增纯 R 比对后端

`aligner = "r"` 使用 `Biostrings::pairwiseAlignment()`：

- 分别把 read 和反向互补 read 比对到参考；
- 选择得分更高的方向；
- 用 `alignment_to_ops()` 把比对结果转换为 SNV / 插入 / 缺失；
- 后续完全复用方案 A 的变异统计和单倍型计数流程。

适用场景：

- Windows；
- ARM 平台；
- 没有 minimap2 二进制的环境；
- 中小规模扩增子数据。

性能示例：30 条 500 bp reads 约 7.4 秒；大规模数据仍建议使用 minimap2。

### 5.3 新增平台与依赖 API

| 函数 | 作用 |
|---|---|
| `nanoamp_platform()` | 返回 `linux-x86_64` 等平台标签 |
| `nanoamp_dependence_dir()` | 定位 `03_dependence/` |
| `nanoamp_tool_path()` | 按优先级解析外部工具 |
| `nanoamp_tool_version()` | 读取工具版本 |

### 5.4 CLI / GUI 新增对齐后端选项

- CLI：`--aligner minimap2|r`；
- GUI：新增 “Alignment backend” 下拉框。

---

## 6. 验证结果

### 6.1 单元测试

```bash
Rscript -e 'devtools::test("02_code/r", reporter = "summary")'
```

通过：

- 核心算法测试；
- `03_dependence` 解析测试；
- R 内比对后端测试；
- GUI `testServer()` 测试。

### 6.2 R CMD check

```text
Status: OK
```

### 6.3 CLI 验证

```bash
sh 02_code/cli/nanoamp doctor
```

输出确认：

```text
platform: linux-x86_64
dependence directory: .../03_dependence
minimap2 .../03_dependence/linux-x86_64/bin/minimap2 (2.31-r1302)
samtools .../03_dependence/linux-x86_64/bin/samtools (samtools 1.12)
```

### 6.4 功能回归

使用内置 minimap2 + Rsamtools 重新跑完整功能测试：

```text
168 / 168 runs OK
Mode A: 163 / 167 company variants = 97.6%
        22 / 23 samples with 100% overlap
Mode B: mean overlap 0.5048
Mode C: mean top1 proportion 0.1231
```

与改造前的 `test_run_2` 相比，方案 A 结果一致（163/167，22/23）。

### 6.5 R 内后端验证

在 30 条 E4-3 reads 上对比：

| 后端 | top1 | 第二 | 第三 |
|---|---|---|---|
| minimap2 | 218delG 40.0% | 参考 26.7% | 218delG+135C>T 23.3% |
| R-native | 220delG 32.1% | 参考 28.6% | 220delG+135C>T 21.4% |

单倍型结构一致；缺失位置标注略有差异（重复区 indel 左对齐问题）。

---

## 7. 已知限制

1. 内置 samtools 是动态链接到系统库的拷贝，不具备完全可移植性；
   推荐使用 Rsamtools 路径，samtools 仅作后备。
2. Windows / ARM 仍没有官方 minimap2 / samtools 二进制；
   这些平台依赖 R 内后端或 WSL2。
3. R 内后端比 minimap2 慢约 4 倍以上，不适合十万级 reads。
4. R 内后端的缺失位置标注在重复区可能与 minimap2 差 1–2 bp。
5. 本轮未在真实 Windows / ARM 机器上执行，只完成了代码路径、CI 配置和文档。
6. `03_dependence` 中的二进制使仓库增大约 10 MB。

---

## 8. 下一步

1. 为 R 内后端做性能优化（`DECIPHER::AlignProfiles`、并行化）；
2. 用 conda-pack 为 Linux ARM64 / macOS 生成可移植工具包；
3. 在 Windows CI 上跑 `aligner = "r"` 的端到端测试；
4. 构建 Windows RInno 安装包，并决定是否随包分发 R 内后端；
5. 继续推进 GTF / CDS 注释；
6. 增加 `--aligner` 到完整功能测试脚本，量化两种后端的一致性。

---

## 9. 复现命令

```bash
# 环境与依赖
sh 02_code/cli/nanoamp doctor

# CLI 单样本（内置 minimap2）
sh 02_code/cli/nanoamp call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --aligner minimap2 --top-n 20 \
  --outdir 04_results/cli/dep_A

# 纯 R 后端（无需 minimap2）
sh 02_code/cli/nanoamp call \
  --reads sample.fastq --reference target.fa \
  --mode A --aligner r --outdir 04_results/cli/r_backend

# GUI
Rscript 02_code/gui/run_gui.R

# 测试
Rscript -e 'devtools::test("02_code/r", reporter = "summary")'
R CMD check --no-manual --no-build-vignettes nanoamp_0.1.0.tar.gz
```

---

## 10. Git 提交

| 提交 | 说明 |
|---|---|
| `fc56ea5` | feat: bundle dependencies, add R-native aligner and fill CLI/GUI entrypoints |

本报告提交后工作区应保持干净；功能测试输出位于 `04_results/r/test_run_3/`，
按约定不进入 Git。
