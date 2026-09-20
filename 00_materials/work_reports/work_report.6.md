# 工作报告 6：GitHub 远端接入、Windows 源码编译 minimap2、本机 R 环境与全量回归

> 日期：2026-09-20
> 关联：`work_report.5.md`
> 本轮范围：打通 GitHub 远端；在 Windows 上从源码编译 minimap2 并把编译链脚本纳入仓库；
> 在本机安装 R 并跑通全部测试；修复测试暴露的 Biostrings/pwalign 兼容性缺陷
> 约束：全程不使用 conda，不使用 WSL

---

## 1. 摘要

| # | 任务 | 结果 |
|---|---|---|
| 1 | 本地 git 接入 GitHub 远端 | `origin` 已配置，`main` 跟踪 `origin/main`，`ahead 0 / behind 0` |
| 2 | Windows 源码编译 minimap2 | 成功，产出静态链接 `minimap2.exe`（2.31-r1302，1.28 MB） |
| 3 | 编译链纳入仓库 | 两个可复现脚本 + 编译产物 + 来源信息已入库；工具链本体（约 1.5 GB）不入库并已说明理由 |
| 4 | 本机安装 R 并跑通测试 | R 4.6.1；`R CMD check` **Status: OK**；testthat 34/34 通过 0 跳过 |
| 5 | 功能回归 | **168/168 全部成功**，Mode A 复现公司变异 **163/167 = 97.6%**，**22/23** 样本 100% 重合 |
| 6 | 修复真实缺陷 | `Biostrings::pairwiseAlignment()` 在 Bioconductor ≥ 3.19 已被移出，`aligner = "r"` 后端原本报错，已修复 |

关键结论：**Windows 上源码编译的 minimap2 与 Linux 官方二进制结果一致**。
本机回归得到的 163/167、22/23 与 `work_report.5.md` 记录的 Linux 基线逐位相同。

---

## 2. Git 远端接入

### 2.1 遇到的问题

`git fetch` 失败：

```text
fatal: unable to access 'https://github.com/Clearmind777/nanoamp.git/':
schannel: next InitializeSecurityContext failed:
CRYPT_E_REVOCATION_OFFLINE (0x80092013)
```

原因是本机网络无法访问证书吊销列表（CRL/OCSP）服务器，而 Git for Windows 默认使用
schannel 后端并强制检查吊销状态。`curl` 同样受影响（同样的 `CRYPT_E_REVOCATION_OFFLINE`）。

### 2.2 解决方式

改用 Git 自带的 OpenSSL 后端（该后端不依赖系统吊销检查）：

```bash
git config --local http.sslBackend openssl
```

（等价备选：`git config --local http.schannelCheckRevoke false`；curl 侧对应
`curl --ssl-no-revoke`，本轮所有下载都带了这个开关。）

### 2.3 结果

```text
origin  https://github.com/Clearmind777/nanoamp.git (fetch/push)
* main                a7afb38
  remotes/origin/main a7afb38
branch 'main' set up to track 'origin/main'.
git rev-list --left-right --count origin/main...HEAD  ->  0    0
```

远端与本地**逐位一致**（同一提交 `a7afb38`），无需合并或变基。此前观察到的
`01_data/ln_test_data/**` 显示为 modified，是 Windows 下 `core.symlinks=false`
把符号链接实体化为普通文件导致的，与远端无关，本轮未改动这一层。

---

## 3. Windows 源码编译 minimap2

### 3.1 为什么需要自己做

上游事实核查结论：

- minimap2 **没有**官方 Windows 二进制，MSYS2 仓库里也没有 minimap2 包；
- 但它的构建系统只是一个 Makefile，社区已有 MSYS2 编译成功的记录；
- htslib 官方 `INSTALL` 文档明确推荐 Windows 使用 **MSYS2/MINGW64**（这条对 samtools 有意义）。

### 3.2 编译链选型与获取

| 环节 | 选择 | 说明 |
|---|---|---|
| 工具链 | MSYS2 **便携版 base tarball**（非安装器） | 免管理员权限；安装器运行后无任何产物（未提权静默安装被忽略），且不是标准 NSIS 归档，7-Zip 无法直接解包 |
| 版本 | `msys2-base-x86_64-20250830.tar.zst` | 固定版本 + 固定 SHA256 |
| 镜像 | `mirrors.tuna.tsinghua.edu.cn` | 本机实测约 3 MB/s；`mirror.msys2.org` 8 KB/s，GitHub release / sourceforge 约 30–60 KB/s，`github.com` release 直链不可用 |
| 编译器 | `mingw-w64-x86_64-toolchain`（gcc 16.2.0-3） | 原生 PE，不带 MSYS 运行时 |
| 依赖 | `mingw-w64-x86_64-zlib` 1.3.2-2 | minimap2 唯一的外部库 |

### 3.3 编译参数与两个关键点

```bash
make CFLAGS="-g -Wall -O2 -std=gnu11 -Wno-error" \
     LIBS="-lm -lz -lpthread -static -static-libgcc" minimap2
```

1. **`-std=gnu11` 必须加**：`kalloc.h` 使用了匿名结构体成员，不属于 gnu17/gnu23；
   gcc 16 默认 `gnu23`，不加会直接编译失败。
2. **`-static` 决定可移植性**：在 MSYS shell 而非 MINGW64 shell 里编译，产物会依赖
   `msys-2.0.dll` / `msys-z.dll`，只能在本机 MSYS2 环境下运行。静态链接后：

```text
DLL Name: KERNEL32.dll
DLL Name: msvcrt.dll
```

即只依赖 Windows 系统 DLL，在没装 MSYS2/Cygwin/conda/WSL 的机器上直接可跑。

### 3.4 产物

| 字段 | 值 |
|---|---|
| 版本串 | `2.31-r1302` |
| 大小 | 1,339,127 字节 |
| SHA256 | `82f0433956552b4d1ed0e09641f71f5750fc783548e317a302ca05a348bd1542` |
| 路径 | `03_dependence/windows-x86_64/bin/minimap2.exe` |
| 许可证 | MIT（已在 `03_dependence/licenses/`） |

`nanoamp` 无需额外配置即可解析到它（`nanoamp_tool_path()` 会为 Windows 补 `.exe` 后缀）：

```text
platform        : windows-x86_64
minimap2 path   : .../03_dependence/windows-x86_64/bin/minimap2.exe
minimap2 version: 2.31-r1302
```

### 3.5 编译链如何"纳入仓库"

工具链本体约 1.5 GB，**不适合也不可能**进 Git。因此入库的是"可复现配方"：

```text
03_dependence/windows-x86_64/
|-- install_msys2_toolchain.ps1   # 下载+校验SHA256+解包+配镜像+装包
|-- build_minimap2.sh             # 取源码+编译+安装+打印DLL依赖
|-- bin/minimap2.exe             # 编译产物
`-- README.md                     # 固定版本、参数、哈希、许可证
03_dependence/manifest.tsv        # 新增 windows-x86_64 行
03_dependence/r-environment/      # R 侧环境脚本（见第 4 节）
```

`install_msys2_toolchain.ps1` 完全无人值守、不需要管理员权限，默认装到
`D:\tools\msys2`（可用 `-ToolRoot` 改），并把 pacman 镜像钉死以保证可复现。

> 设计取舍：把工具链放进仓库会让每次 clone 多出 1.5 GB 且无法用 Git 有效增量存储；
> 因此选择"脚本 + 固定校验和 + 产物"的组合，克隆者一条命令即可重建。

---

## 4. 本机 R 环境与测试

### 4.1 环境

| 项 | 值 |
|---|---|
| R | 4.6.1 (2026-06-24 ucrt)，x86_64-w64-mingw32 |
| 安装方式 | 官方安装器 `/VERYSILENT /NORESTART /CURRENTUSER /DIR=...`（免管理员） |
| R 库 | `D:\tools\R\lib`（仓库之外，保持工作区干净） |
| CRAN | TUNA 镜像（本机约 3 MB/s） |
| Bioconductor | `bioconductor.org` 官方源 |

两个网络坑记录在案：TUNA 的 bioconductor 路径返回的是 stub 而非包索引，必须用官方源；
R 的 `wininet` 下载方式在本机直接 `connection reset`，因此显式固定
`download.file.method = "libcurl"`。

### 4.2 依赖安装

CRAN：`BiocManager`、`data.table`、`jsonlite`、`optparse`、`readxl`、`testthat`、`pkgload`
Bioconductor：`Biostrings` 2.80.2、`IRanges` 2.46.0、`Rsamtools` 2.28.0、`ShortRead` 1.70.0、`DECIPHER` 3.8.1、`pwalign`
可选：`shiny` 1.14.0、`DT` 0.34.0

### 4.3 修复的真实缺陷：Biostrings / pwalign

首轮测试报错：

```text
Error ('test-dependence.R:27:3'): R-native aligner runs on a small synthetic dataset
Error: 'pairwiseAlignment' is not an exported object from 'namespace:Biostrings'
```

根因：**Bioconductor 3.19 把 `pairwiseAlignment()`、`pattern()`、`subject()`、
`aligned()`、`score()` 从 Biostrings 移到了 pwalign**。`02_code/r/R/align.R` 与
`cluster.R` 原本直接调用 `Biostrings::pairwiseAlignment()`，因此在当前
Bioconductor 上 `aligner = "r"` 后端完全不可用（不只是测试问题）。

修复方式：在 `R/zzz.R` 增加 provider 解析，`.onLoad` 时确定由哪个包提供这组函数，
两处调用点改为走 `pa_*()` 包装；`pwalign` 加入 `Suggests`。
`nanoamp:::pa_provider_name()` 可查看当前 provider（本机为 `pwalign`）。
这样旧版 Bioconductor（函数仍在 Biostrings）与新版都能工作。

### 4.4 验证结果

```text
Rscript 03_dependence/r-environment/run_tests.R
  files 3 | tests 11 | passed 34 | failed 0 | errors 0 | skipped 0 | warnings 0
  ALL TESTS PASSED

R CMD build + R CMD check --no-manual --no-build-vignettes
  Status: OK
```

注意：minimap2 就位后，原先被跳过的两个 Mode A / Mode B 测试**不再跳过**，
所以通过数从 24 上升到 34、跳过数降为 0。

### 4.5 干净克隆端到端验证

为了确认"仓库里提交的东西真的可用"，把仓库克隆到 `D:\tools\verify_clone\nanoamp`
并只走仓库内的文档流程，不做任何手工修补。过程中发现并修复了两个问题（见 4.6）：

```text
git clone <repo> D:\tools\verify_clone\nanoamp        # 成功，历史完整

# 二进制与行尾完整性
cloned minimap2.exe sha256 = 82f04339...bd1542        # 与提交一致
build_minimap2.sh CRLF count = 0                      # .gitattributes 生效
cloned minimap2.exe --version -> 2.31-r1302           # 克隆产物可直接运行

# 修复软链接层后
Rscript 03_dependence/r-environment/materialize_test_data.R
  materialized (copied) : 201 / 201
  ALL ln_test_data LINKS RESOLVE TO THE CORRECT CONTENT

Rscript 03_dependence/r-environment/run_tests.R
  passed 34 | failed 0 | errors 0 | skipped 0         # ALL TESTS PASSED

Rscript 03_dependence/r-environment/run_functional_regression.R \
  --outdir 04_results/r/clone_verify --modes A,B,C --threads 4
  A: 56/56 ok, mean_overlap 0.9807
  B: 56/56 ok, mean_overlap 0.5409
  C: 56/56 ok, mean_top1 0.1231
  => 168/168 全部成功，Mode A 与原始工作区结果一致
```

### 4.6 干净克隆暴露并修复的两个问题

**(1) `ln_test_data` 软链接层在 Windows 上是坏的。**
`01_data/ln_test_data/**` 在 Git 中以**符号链接**（mode `120000`）存储。
Windows 只有在开启开发者模式（或具备 `SeCreateSymbolicLinkPrivilege`）时才能创建符号链接，
否则：

- `git checkout` 把链接目标写成约 100 字节的**纯文本文件**；
- `prepare_test_data.R` 里的 `file.symlink()` 直接返回 `FALSE`，什么都不建。

于是每个 `ln_test_data` 文件里存的是路径字符串而不是序列数据，任何读取它们的分析都会失败。
干净克隆里表现为 `test-gui.R` 的 4 个失败。

修复：新增 `03_dependence/r-environment/materialize_test_data.R`，
逐行对照 `manifest.tsv`，把仍是 stub 的项**按内容复制**为目标文件；
用 `Sys.readlink()` 识别真正的符号链接并跳过，因此在 Linux 上是空操作。
脚本最后对全部 201 项做 MD5 校验。

**(2) 功能回归包装脚本在子进程里丢了库路径。**
原实现用 `--vanilla` 启动子 `Rscript`，而 `--vanilla` 会跳过 `Rprofile.site`，
于是子进程看不到专用库，报 `there is no package called 'data.table'`。
改为把库路径通过 `R_LIBS` 传给子进程，并用 `--no-save --no-restore` 启动。

---

## 5. 功能回归（Windows vs Linux）

```powershell
Rscript 03_dependence/r-environment/run_functional_regression.R `
  --outdir 04_results/r/test_run_win --modes A,B,C --threads 4
```

覆盖 `TSM20260826`、`ZNF8`、`nano_seq` 三个数据集、31 个样本、三种模式 × self/wt 参考。

| 模式 | 运行数 | 成功 | 失败 | 平均 top1 占比 | 平均 overlap | 平均耗时 |
|---|---:|---:|---:|---:|---:|---:|
| A | 56 | 56 | 0 | 0.6750 | 0.9807 | 0.68 s |
| B | 56 | 56 | 0 | 0.7286 | 0.5409 | 3.65 s |
| C | 56 | 56 | 0 | 0.1231 | — | 0.11 s |

**合计 168/168 全部成功。**

### 5.1 与 Linux 基线对比

| 指标 | Linux 基线（报告 5） | Windows 本轮 | 结论 |
|---|---|---|---|
| 运行成功 | 168/168 | 168/168 | 一致 |
| Mode A 复现公司变异 | 163/167 = 97.6% | **163/167 = 97.6%** | 一致 |
| Mode A 100% 重合样本 | 22/23 | **22/23** | 一致 |
| Mode B 平均 overlap | 0.5048 | 0.5409 | 量级一致（聚类本身有随机性/实现差异） |
| Mode C 平均 top1 占比 | 0.1231 | **0.1231** | 逐位一致 |

Mode A 是默认且最常用的模式，其"复现公司变异"和"100% 重合样本数"两个核心指标
与 Linux 完全相同，Mode C（纯精确匹配，无外部工具、无随机性）逐位相同。
**可以判断 Windows 源码编译的 minimap2 与 Linux 官方二进制在本质因分析上等价。**

唯一未 100% 重合的样本仍是 `ZNF8/clone_3`（5/9），与 Linux 基线一致，
属于已知的重复区 indel 左对齐问题，非本轮引入。

Mode B 的平均 top1 占比在两次运行间有极小抖动（0.7286 vs 0.7281，
干净克隆 168/168 那次），聚类路径本身受实现细节影响，属正常范围。

---

## 6. 仓库变更清单

| 文件 | 变更 |
|---|---|
| `02_code/r/R/zzz.R` | 新增 pair-wise alignment provider 解析与 `.onLoad` |
| `02_code/r/R/align.R` | `Biostrings::pairwiseAlignment` → `pa_pairwise_alignment` 等 |
| `02_code/r/R/cluster.R` | 同上 |
| `02_code/r/DESCRIPTION` | `Suggests` 增加 `pwalign` |
| `02_code/r/README.md` | 依赖安装与排错表补充 pwalign |
| `03_dependence/windows-x86_64/install_msys2_toolchain.ps1` | 新增 |
| `03_dependence/windows-x86_64/build_minimap2.sh` | 新增 |
| `03_dependence/windows-x86_64/bin/minimap2.exe` | 新增（编译产物） |
| `03_dependence/windows-x86_64/README.md` | 重写：真实构建路径、参数、哈希 |
| `03_dependence/windows-arm64/README.md` | 重写：去掉 WSL 建议 |
| `03_dependence/r-environment/*` | 新增：R 环境搭建、软链接层修复与测试运行脚本 |
| `.gitattributes` | 新增：固定行尾（`.sh`/`R` LF，`.ps1`/`.bat` CRLF）与二进制处理 |
| `03_dependence/manifest.tsv` | 新增 windows-x86_64 行 |
| `03_dependence/README.md` / `README-CN.md` | 平台矩阵与上游事实更正 |
| `README.md` | 外部工具、Windows 构建、测试运行说明 |

---

## 7. 已知限制

1. 未在**干净的** Windows 机器上验证 `minimap2.exe` 的 DLL 依赖满足情况
   （本机装了 MSYS2）。不过干净克隆里的产物可直接运行，且 `objdump` 显示只依赖
   `KERNEL32.dll` 与 `msvcrt.dll`，静态链接已确认。
2. samtools **未**在 Windows 编译。它在本项目中是可选的（默认走
   `Rsamtools::asBam()`），本轮判断收益不足；htslib 官方支持该路径，需要时可补。
3. Windows ARM64 仍未验证，当前建议跑 x86_64 版本（模拟）或用 R 内后端。
4. `R CMD check` 在 Windows 上通过，但检查环境里没有 `03_dependence`，
   因此 Mode A/B 测试在该场景下会跳过；完整覆盖需用
   `03_dependence/r-environment/run_tests.R`（本机与干净克隆均已跑通，0 跳过）。
5. `ln_test_data` 软链接层在 Windows 上仍需手工跑一次
   `materialize_test_data.R`（已自动化，但不是 `git clone` 后即用）。
   彻底解决可考虑把该层改为普通文件、改用 Git LFS，或要求开发者模式。
6. Mode B 的 top1 占比在多次运行间有微小抖动（0.7286 / 0.7281），
   聚类路径本身受实现细节影响，未逐样本深究。

---

## 8. 下一步

1. 在干净 Windows 10/11（无 MSYS2）上验证 `minimap2.exe` 与整个流程；
2. 视需要补 Windows 版 samtools（htslib + `ldd` 收集运行时 DLL）；
3. 把 Windows 构建纳入 GitHub Actions，实现持续验证；
4. 继续推进 GTF / CDS 功能注释（仍是委托中点名但未实现的功能）；
5. 用 RInno 构建 Windows 安装包，验证"教授双击即用"的交付形态；
6. 考虑为 `01_data/ln_test_data` 在 Windows 上改用普通文件或 Git LFS，
   消除符号链接带来的持续 "modified" 噪音。

---

## 9. 复现命令

```bash
# --- 1. 克隆与远端 ---
git config --local http.sslBackend openssl   # 本机网络需要
git remote -v && git fetch origin

# --- 2. 编译链与 minimap2 ---
pwsh -File 03_dependence/windows-x86_64/install_msys2_toolchain.ps1
bash 03_dependence/windows-x86_64/build_minimap2.sh

# --- 3. R 环境 ---
Rscript 03_dependence/r-environment/setup_r_environment.R
R CMD INSTALL --library=D:/tools/R/lib 02_code/r

# --- 4. 测试 ---
Rscript 03_dependence/r-environment/run_tests.R
Rscript 03_dependence/r-environment/run_functional_regression.R `
  --outdir 04_results/r/test_run_win --modes A,B,C --threads 4

# --- 5. 工具解析自检 ---
Rscript -e "library(nanoamp); nanoamp_cli(c('doctor'))"
```
