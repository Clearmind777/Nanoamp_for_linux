# 工作报告 10：落实三项加固——glibc 交叉下载、FASTQ 自研解析器、依赖文档校准

> 日期：2026-09-23
> 关联：`work_report.9.md`（四平台预置二进制与 pak 优先依赖安装）
> 触发：拉取远端 `2bc4bc5`、`3557229` 两个修正提交后的验证（见下）
> 本轮范围：
> 1. `fetch_dependencies.sh` 在 macOS 上无法交叉下载 linux-x86_64 —— 修掉；
> 2. 文档声称"minimap2-only 流程不需要 pwalign" —— 在依赖栈层面**真正实现**它，
>    而不是改措辞：用 base R 的 FASTQ 解析器替换 `ShortRead`；
> 3. 同步 `DESCRIPTION`、`doctor`、各级文档，使依赖描述与实际一致；
> 4. 验证后提交推送。

---

## 1. 起点：远端两个修正提交

拉取（`8a5c4ac → 3557229`，fast-forward）得到两个提交，都指向第 9 轮的真实缺陷：

| 提交 | 修正 |
|---|---|
| `2bc4bc5` | pairwise 提供者改为**惰性解析**（第 9 轮在 `.onLoad` 里主动解析，导致缺 pwalign 时连 `library()` 都失败） |
| `3557229` | linux-x86_64 换成真正的 2.31（第 9 轮那份实际是 **2.28-r1209**，而 manifest/README 都写 2.31） |

验证结论：四平台版本已统一为 `2.31-r1302`、4/4 sha256 与 manifest 一致、glibc 基线
（2.14 / 2.17）与文档一致、功能测试 168/168、`R CMD check` Status: OK。

同时发现两个遗留问题，即本轮要解决的三件事。

---

## 2. 问题一：`fetch_dependencies.sh` 在 macOS 上无法刷新 linux-x86_64

### 现象

`3557229` 为防止版本漂移加了固定 `minimap2=2.31`，但该固定版本在 macOS 宿主上
**求解直接失败**：

```text
error  libmamba Could not solve for environment specs
  └─ minimap2 =2.31 * is not installable because it requires
     └─ __glibc >=2.17,<3.0.a0 *, which is missing on the system.
warning  libmamba glibc version not found (virtual package skipped)
```

根因：`__glibc` 是**宿主**虚拟包，conda 只在 Linux 宿主上提供它；macOS 上交叉求解
linux-64 时不存在，激活 conda base 也没用。而**去掉固定版本反而能装成**——装到的是
`2.28-r1209`，也就是脚本会复现当初那个"版本悄悄漂移"的 bug。

逐平台实测（macOS arm64 宿主，`--no-deps minimap2=2.31`）：

| conda subdir | 不带覆盖变量 | 带 `CONDA_OVERRIDE_GLIBC=2.17` |
|---|---|---|
| linux-64 | **失败**（缺 `__glibc`） | 成功 → 2.31-r1302 |
| linux-aarch64 | 成功 → 2.31-r1302 | 成功 → 2.31-r1302 |
| osx-64 / osx-arm64 | 成功 → 2.31-r1302 | — |

即只有 linux-64 受影响。

### 修复

`fetch_dependencies.sh` 在调用 conda 时统一带上
`CONDA_OVERRIDE_GLIBC="${CONDA_OVERRIDE_GLIBC:-2.17}"`：

- 只影响求解，不改变产物；
- 2.17 与预置 Linux 二进制**实际需要的运行时下限**一致（由 ELF 动态段核实），
  不会虚报宿主能力；
- 对 macOS 两个 subdir 无副作用；
- 允许调用方用环境变量覆盖（设为 0 即回到宿主真实虚拟包）。

**验证**：实测重新下载得到的二进制 sha256 精确等于 `manifest.tsv` 记录值
`b6c81294dc0b68b2f54f8e2f6f3ad6be71a40bccc47a6e244ecebc73bae9501d`，即固定版本
现在**可复现**。

---

## 3. 问题二：文档关于"不需要 pwalign"的说法与依赖栈矛盾

### 现象

`README.md` 写"the package loads and completes an analysis even when `pwalign` is
not installed"。前半句（能加载）在 `2bc4bc5` 后成立；**后半句不成立**：

```text
ShortRead 1.68.0   Imports: Biobase, S4Vectors, IRanges, Seqinfo,
                            GenomicRanges, pwalign, hwriter, methods, ...
```

`ShortRead` 是 nanoamp 的**硬依赖**（`R/io.R` 用它读 FASTQ），而它在 `Imports` 里
**无条件**依赖 `pwalign`。实测（临时移走 pwalign 目录）：

- `library(nanoamp)` → OK（惰性修复生效）
- 任何真正读 FASTQ 的分析 → 失败，错误为 `there is no package called 'pwalign'`，
  且归因到 `ShortRead` 而非 pairwise 逻辑
- 另测 `library(ShortRead)` → 同样报缺 pwalign，确认根因在 ShortRead

也就是说，缺 pwalign 的机器上"能装、能 `doctor`，但第一次分析就崩，且错误信息误导"。

### 决定：把声明变成事实，而不是改措辞

`ShortRead` 在 nanoamp 里只用了四处，全部集中在 `R/io.R`：
`readFastq`、`id`、`sread`、`countFastq`。既然 quality 列**下游没有任何消费者**
（`grep` 确认），完全可以用一个小型 base R 解析器替代，从而**真正**去掉这个传递依赖。

### 实现

新增 `R/io.R` 内部函数：

| 函数 | 作用 |
|---|---|
| `fastq_connection(path)` | 按扩展名**和** gzip 魔数（`1f 8b`）判断是否 gz，避免误标文件被当文本读 |
| `read_fastq_records(path, block)` | 分块（默认 20000 条/块）读入，每块校验"4 行一条"、"每第 1 行以 `@` 开头"、"每第 3 行以 `+` 开头"，不符即**显式报错** |
| `read_fastq(path)` | 返回 `read_id` / `sequence` / `quality`；`read_id` **去掉前导 `@`**（与 `ShortRead::id()` 一致）；序列转大写 |
| `count_fastq_reads(path)` | 分块只数记录数，不构造大表 |

格式假设与安全性：只支持"一条记录 4 行、序列不折行"——这正是所有现代 basecaller 与
公司交付文件的格式，已对本仓库 32 个真实 FASTQ **逐一校验**（行数为 4 的倍数、
头部 `@`、分隔 `+`、序列与质量等长，**32/32 通过**）。折行记录会被明确拒绝，
而不是被静默错解。

### 等价性验证（关键）

在移除 `ShortRead` **之前**，用 `tmp/fastq_compat.R` 对全部 32 个真实 FASTQ 做逐条
对比，覆盖 4118 条记录：

| 维度 | 结果 |
|---|---|
| 记录数 | 32/32 完全一致 |
| `read_id`（去 `@` 后） | 32/32 完全一致 |
| `sequence` | 32/32 完全一致 |
| `quality` | 0 个文件逐字节相同；32/32 满足"参考 = 候选 + 填充" |

quality 的差异是**修正了一个既有缺陷**，而不是回归。原来 `R/io.R` 把
`methods::as(quality(fq), "matrix")` 得到的矩阵**逐行整行**转字符：该矩阵宽度是
**该文件最长 read 的长度**（实测 375 × 2491），短 read 右侧由 `NA` 填充，而
`as.integer(NA) -> 0 -> raw(33) -> "!"`，于是每条 read 的 quality 字符串都被补到
最长长度、填充字符为 `!`（即 Phred 0，与"真实最低质量"无法区分）。

新解析器返回**与该 read 序列等长**的正确质量串。因为 quality 列下游无人消费，
该修正不影响任何分析结果——功能测试结果不变即为佐证。

### 效果（实测，临时移走 pwalign 目录）

| 场景 | 修复前 | 修复后 |
|---|---|---|
| `library(nanoamp)` | OK | OK |
| 方案 A + 预置 minimap2 | **崩**（`there is no package called 'pwalign'`） | **OK**，`qc.pairwise_provider = NA` |
| 方案 C | **崩**（同上） | **OK** |
| 方案 A + `aligner="r"` | 崩（错误归因误导） | 明确的 `Pairwise alignment is unavailable...` |
| 方案 B | 崩（同上） | 同上，明确报错 |

即"minimap2-only 流程不需要 pwalign"现在**在依赖栈层面成立**。

---

## 4. 问题三：同步依赖描述

| 文件 | 改动 |
|---|---|
| `02_code/DESCRIPTION` | `Imports` 移除 `ShortRead`（9 个包） |
| `02_code/R/cli.R` | `doctor` 的包清单移除 `ShortRead`、加入 `pwalign`，并注明 ShortRead 不再使用 |
| `02_code/README.md` / `-CN.md` | 依赖清单去掉 ShortRead；说明为何去掉；校正惰性提供者一节 |
| `02_code/inst/docs/INSTALL_DEPENDENCIES{,-CN}.md` | 必需清单去掉 ShortRead 并解释原因；说明只有 `aligner="r"` 与方案 B 标注需要提供者 |
| `README.md` | "Two different alignments" 一节补充 FASTQ 由 `R/io.R` 解析的事实 |
| `03_dependence/README{,-CN}.md` | 新增固定版本的由来与 `CONDA_OVERRIDE_GLIBC` 的说明 |
| `02_code/tests/testthat/test-core.R` | 新增 3 组 FASTQ 解析器测试 |
| `00_materials/README.md` | 报告清单加入本报告 |

`00_materials/work_reports/1–9` 作为历史日志**原样保留**，不改写（其中提到
ShortRead / pwalign 的内容反映当时状态）。

---

## 5. 验证

| 检查 | 结果 |
|---|---|
| FASTQ 解析器 vs ShortRead（32 文件 / 4118 条） | 记录数、id、序列 100% 一致；quality 为"修正后的正确长度" |
| `make test`（含新增 3 组 FASTQ 测试） | 全部通过 |
| gzip 路径 | 明文与 gz 读取结果 `identical()`，`count_fastq_reads` 一致 |
| 畸形输入 | 行数非 4 的倍数、非 FASTQ 文件均 `Malformed FASTQ` 明确报错 |
| 功能测试（3 数据集 × 32 样本 × A/B/C） | **168/168 ok**；A=0.6750/0.9807、C=0.1231，与基线一致 |
| 无 pwalign 场景 | 方案 A / C 可用，方案 B 与 `aligner="r"` 明确报错 |
| `R CMD check` | **Status: OK** |
| `fetch_dependencies.sh --platform linux-x86_64` | 带覆盖变量后 sha256 与 manifest **精确一致** |

---

## 6. 现状与已知限制

- 依赖从 10 个降到 9 个（Bioconductor 从 4 个降到 3 个）；
- 缺 pwalign 的机器上默认流程可用（方案 A / C），只有方案 B 与 `aligner="r"` 需要它；
- FASTQ 解析器是自研代码，属新的维护面：只接受严格 4 行格式，折行 FASTQ 会报错。
  若今后遇到折行数据，需要扩展该解析器（而不是回退到 ShortRead，否则会重新引入
  pwalign 硬依赖）；
- quality 列现在的语义是"逐 read 等长"，与第 9 轮及更早的输出**不同**（旧值被填充到
  文件最长 read）。由于该列无下游消费者，未视为破坏性变更，但如需对外承诺，
  应在输出契约里明确；
- linux-arm64 的预置二进制仍无法在本机实跑验证（架构不同），只能靠 ELF 解析核实。
