# 工作报告 9：四平台预置二进制与 pak 优先的 R 依赖安装

> 日期：2026-09-22
> 关联：`work_report.8.md`
> 本轮范围：
> 1. 解决“预置二进制只有 Linux x86_64、其余平台用不了”的问题，为
>    **linux-x86_64 / linux-arm64 / macos-x86_64 / macos-arm64 四个平台全部预置
>    minimap2**；
> 2. 按“samtools 用 Rsamtools 代替”的原则不再预置 samtools；
> 3. 无法预置的 R 包依赖，改为 **pak 优先**、失败回退
>    `install.packages()` + `BiocManager::install()`；
> 4. 在 macOS arm64 上重新完成端到端验证；
> 5. 提交并推送远端。

---

## 1. 问题的确认

第 8 轮报告里写过“随附的 Linux 二进制在 macOS 上无法执行”，本轮把这件事查到底：

```text
03_dependence/
|-- linux-x86_64/bin/{minimap2,samtools}   # 只有这里有真实文件
|-- linux-arm64/README.md                  # 只有说明
|-- macos-x86_64/README.md                 # 只有说明
`-- macos-arm64/README.md                  # 只有说明
```

也就是说**四个平台里只有一个真正有二进制**，这台 arm64 mac 以及所有 Intel/ARM
组合都只能自己装 conda。直接执行会得到：

```text
./03_dependence/linux-x86_64/bin/minimap2: cannot execute binary file
```

## 2. 方案：预置四个平台，但**不要求用户装 conda**

### 2.1 为什么 conda-forge 的构建可以“预置”

上游 minimap2 只发布 Linux x86_64 预编译包，Linux arm64 与两种 macOS 架构都没有
官方构建。conda-forge 四个平台都构建，而且它的构建产物**运行时不需要 conda**——
这正是能够“预置”的前提。逐平台核实：

| 平台 | 文件格式 | 链接到的库 | glibc 基线 |
|---|---|---|---|
| linux-x86_64 | ELF x86-64 (PIE) | `libm`, `libz`, `libpthread`, `libc` | 2.14 |
| linux-arm64 | ELF AArch64 (PIE) | `libm`, `libz`, `libpthread`, `libc`, `ld-linux-aarch64` | 2.17 |
| macos-x86_64 | Mach-O x86_64 | `/usr/lib/libSystem.B.dylib` + 系统 zlib | — |
| macos-arm64 | Mach-O arm64 | `/usr/lib/libSystem.B.dylib` + 系统 zlib | — |

核实手段：ELF 用 `file` 加解析 `.dynamic` 段的 `DT_NEEDED`，Mach-O 用 `otool -L`；
macOS arm64 那份还额外拷到 `/tmp` 并用 `env -i` 清空环境变量执行，确认脱离 conda
仍然输出 `2.31-r1302`。两处非系统库都落在 glibc / macOS 自带范围内，因此可以随仓库
分发。Linux 侧最低要求 glibc 2.14 / 2.17（CentOS 7、Ubuntu 16.04 即满足）。

### 2.2 为什么不用 Docker

四份二进制全部用 `mamba` 的 `CONDA_SUBDIR` **交叉下载**获得，一台 macOS 机器就能
取到另外三个平台的包：

```bash
CONDA_SUBDIR=linux-64      mamba create -y -p /tmp/env -c conda-forge --no-deps minimap2
CONDA_SUBDIR=linux-aarch64 mamba create -y -p /tmp/env -c conda-forge --no-deps minimap2
CONDA_SUBDIR=osx-64        mamba create -y -p /tmp/env -c conda-forge --no-deps minimap2
```

（本机的 Docker 守护进程未运行，即使可用也不需要——Linux arm64 在 QEMU 下跑
minimap2 会很慢，交叉下载反而更简单可靠。`--no-deps` 可行，因为预置二进制不依赖
任何 conda 提供的共享库。）

### 2.3 为什么不再预置 samtools

`Rsamtools::asBam()` 已经承担 SAM→BAM，`use_samtools` 在全部调用链上的默认值都是
`FALSE`，因此 samtools 只是可选的替代路径。而它**不适合预置**：实测
conda-forge 的 samtools 依赖 `libhts.3.dylib`、`libtinfow.6.dylib`、
`libncursesw.6.dylib` 三个 conda 私有库，要预置就得连这些库和 rpath 一起打包，体积
和复杂度都上一个台阶，收益却接近于零。

结论：**只预置 minimap2，samtools 从仓库移除**，`use_samtools = TRUE` 仍保留为
“机器上恰好有 samtools 时”的出口。`nanoamp doctor` 现在会明确标注：

```text
samtools     NOT FOUND (optional; Rsamtools is used by default)
```

### 2.4 预置结果

```text
03_dependence/                       # 共 2.6 MB
|-- manifest.tsv                     # 四行，含版本/来源/sha256/运行时要求
|-- fetch_dependencies.sh            # 支持 --all 与 --platform，交叉下载
|-- licenses/minimap2-LICENSE.txt
|-- linux-x86_64/{README.md,bin/minimap2}     1.0 MB
|-- linux-arm64/{README.md,bin/minimap2}      1.0 MB
|-- macos-x86_64/{README.md,bin/minimap2}     284 KB
`-- macos-arm64/{README.md,bin/minimap2}      245 KB
```

四份都是 minimap2 2.31-r1302。linux-x86_64 那份同时从上游预编译包换成了
conda-forge 版本，使四个平台共用同一版本与同一构建配方（上游没有 arm64/macOS 版本
本来就是无法统一的原因）。

## 3. R 包依赖：pak 优先

`minimap2` 可以预置，R 包不行（要跟宿主的 R 版本、架构、系统库匹配）。因此新增
`02_code/scripts/install_r_deps.R`，按你的要求分层：

1. **`pak::pak()` 优先**：pak 会一次性解析 CRAN + Bioconductor 依赖图，并复用
   CRAN / Bioconductor 为 macOS（arm64 与 x86_64）和 Windows 发布的**预编译二进制**，
   避免长时间源码编译；
2. pak 缺失时先尝试 `install.packages("pak")` 装上它；
3. pak 不可用或失败，回退 `install.packages()` + `BiocManager::install()`；
4. 结束时逐一复查是否真的装上，未装齐则以退出码 1 报出清单。

配套：`make deps-r` 目标；`make deps` / `make deps-all` 仍用于刷新二进制。

## 4. 验证（macOS arm64）

| 检查 | 结果 |
|---|---|
| 预置二进制在空环境下独立执行（`env -i`） | `2.31-r1302` |
| `PATH` 中移除 conda 工具后 `doctor` 解析路径 | `03_dependence/macos-arm64/bin/minimap2`（仓库内） |
| `nanoamp_tool_path("minimap2")` | 返回仓库内预置路径 |
| `make test`（testthat） | 全部通过，无跳过 |
| `make check`（`R CMD build` + `R CMD check`） | **Status: OK** |
| 功能测试（3 数据集 × 32 样本 × 模式 A/B/C） | **168/168 全部 ok** |
| `fetch_dependencies.sh` 实跑 | 重新下载后 sha256 与 `manifest.tsv` **完全一致** |
| 四份二进制 sha256 复核 | 4/4 与 manifest 一致 |

功能测试结果与第 8 轮（用 conda 的 minimap2）对比：

| 模式 | 平均 top1 占比（第 8 轮 → 本轮） | 与公司变异表平均重合率 |
|---|---|---|
| A | 0.6750 → 0.6750 | 0.9807（不变） |
| B | 0.7253 → 0.7246 | 0.5409（不变） |
| C | 0.1231 → 0.1231 | 0（不变） |

换成预置二进制后结果不变；模式 B 的极小差异来自 DECIPHER 聚类/共识的既有随机性，
与二进制无关。

## 5. 文档更新

| 文件 | 改动 |
|---|---|
| `README.md` / `README-CN.md` | 安装章节拆成两条路径（A: conda；B: 复用已有 R + `install_r_deps.R`）；明确“minimap2 无需安装、已预置”；平台表改为四平台各自的预置文件与 glibc 基线 |
| `03_dependence/README.md` / `-CN.md` | 重写：平台矩阵、为什么取自 conda-forge、交叉下载方式、`doctor` 期望输出、许可证 |
| `03_dependence/{linux-x86_64,linux-arm64,macos-x86_64,macos-arm64}/README.md` | 每个平台各自的文件、来源、sha256、运行时要求与验证命令；linux-x86_64 那份为新增 |
| `03_dependence/manifest.tsv` | 四行，替换原两行（原 samtools 行删除） |
| `03_dependence/fetch_dependencies.sh` | 重写：`--all` / `--platform` / 自动探测；交叉下载并打印 sha256 |
| `02_code/inst/docs/INSTALL_DEPENDENCIES{,-CN}.md` | 重写：依赖表加入“获取方式”列；“安装 minimap2”降级为“通常不需要”；新增 pak 优先的自动安装小节；验证清单更新为预置路径 + samtools 可选标注 |
| `02_code/R/cli.R` | `doctor` 对缺失工具给出更有意义的提示（samtools 标注可选，minimap2 提示预置位置或 `aligner = "r"`） |
| `Makefile` | 新增 `deps-r`、`deps-all`，`deps` 说明改为“刷新预置 minimap2” |
| `00_materials/README.md` | 报告清单加入本报告 |

历史材料仍按既有约定保留在 `00_materials/`，不改写。

## 6. 现状与已知限制

现状：**刚克隆下来、不装 conda、不联网，就能在四个平台上直接跑方案 A/B**（只要 R
包依赖已装）。R 包依赖由 `Rscript 02_code/scripts/install_r_deps.R` 一条命令搞定。

已知限制：

1. **linux-arm64 的预置二进制未在本机实跑**：本机是 macOS arm64，只能在 Linux arm64
   宿主上验证。其架构、链接库与 glibc 基线已通过 ELF 解析核实，但“能跑起来”这一步
   需要一台 Linux arm64 机器确认。
2. **极旧的 glibc**（低于 2.14 / 2.17）无法使用预置二进制，此时用 `aligner = "r"`，
   或自行编译 minimap2。
3. **macOS 预置二进制未做代码签名 / 公证**：从仓库直接执行会在个别严格环境下触发
   Gatekeeper。当前用 `chmod +x` 即可；若日后需要分发 .app 或 pkg，再考虑签名。
4. **samtools 不再预置**：需要 samtools 路径的用户须自行安装（conda/brew/apt），
   否则保持默认的 `Rsamtools`。
5. 方案 B 的 DECIPHER 距离矩阵警告仍然存在（第 8 轮已记录），本轮未改动其行为。
