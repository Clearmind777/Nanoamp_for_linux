# 工作报告 7：Linux 仓库收敛为纯命令行版本

> 日期：2026-09-21
> 关联：`work_report.6.md`
> 本轮范围：按新的仓库定位要求，把 Linux 仓库收敛为**只保留命令行版本**；
> 删除“开箱即用”离线运行时；重写根目录 README 为「程序介绍 + conda 安装」
> 约束：只提交，不推送

---

## 1. 背景与目标

上一轮（`work_report.6.md`）为了让 Linux x86_64 系统「开箱即用」，仓库内置了
一个可移植的 R 4.4.3 运行时（7 个分片，约 573 MB），并附带 CLI / GUI 启动器。

新的仓库定位要求：

1. Linux 仓库只保留**命令行版本**，“开箱即用”部分的文件与内容全部删除；
2. 根目录 `README.md` 只保留**程序介绍**与**安装流程**，安装流程只使用 conda；
3. 原（跨平台）仓库改为纯 R 包仓库（在另一个仓库中单独执行）；
4. 完成后只提交，禁止推送。

---

## 2. 删除的“开箱即用”内容

| 文件 / 目录 | 说明 |
|---|---|
| `03_dependence/linux-x86_64/nanoamp-r-runtime.tar.gz.part00..06` | 便携 R 运行时（7 分片，约 573 MB） |
| `03_dependence/linux-x86_64/nanoamp-r-runtime.tar.gz.sha256` | 分片校验文件 |
| `03_dependence/linux-x86_64/nanoamp` | 首次运行自动解包运行时的 CLI 包装器 |
| `03_dependence/linux-x86_64/nanoamp-gui` | 对应的 GUI 包装器 |
| `03_dependence/linux-x86_64/activate.sh` | 交互式激活脚本 |
| `03_dependence/linux-x86_64/build_runtime.sh` | 运行时构建脚本 |
| `03_dependence/linux-x86_64/README.md` | 离线运行时说明文档 |
| `03_dependence/build/`（未跟踪） | conda-pack 构建暂存环境（约 1.5 GB），已从磁盘清理 |
| `03_dependence/linux-x86_64/nanoamp-r-runtime/`、`*.tar.gz`（未跟踪） | 解包/重组产物，已从磁盘清理 |

保留内容：`03_dependence/linux-x86_64/bin/{minimap2,samtools}` —— 命令行版本仍然
需要这两个外部工具。

同步删除的文档与配置：

- `03_dependence/README.md` / `README-CN.md` 中的「Linux x86_64 离线运行时」章节；
- `03_dependence/manifest.tsv` 中的 `nanoamp-r-runtime` 行；
- `.gitignore` 中的运行时构建/暂存条目。

---

## 3. 只保留命令行版本

GUI 属于 Windows 仓库的职责（预期仓库 `a_09_18_26_mapping_programs_dev_for_win`），
从 Linux 仓库彻底移除：

| 文件 | 说明 |
|---|---|
| `02_code/gui/`（全部） | 仓库级 Shiny GUI 入口与启动器 |
| `02_code/r/R/gui.R` | R 包内的 Shiny 界面代码 |
| `02_code/r/inst/shiny/app.R` | 独立 Shiny 入口 |
| `02_code/r/inst/scripts/nanoamp-gui` | 包内 GUI 启动脚本 |
| `02_code/r/man/nanoamp_gui.Rd`、`nanoamp_gui_app.Rd` | GUI 帮助文档 |
| `02_code/r/tests/testthat/test-gui.R` | GUI 测试 |
| `Makefile` 的 `gui` 目标 | — |

随之同步：

- `02_code/r/NAMESPACE` 去掉 `export(nanoamp_gui)` / `export(nanoamp_gui_app)`；
- `02_code/r/DESCRIPTION` 的 `Suggests` 去掉 `shiny`、`DT`；
- `02_code/README.md` / `README-CN.md`、`02_code/r/README*.md` 去掉 GUI 章节与
  相关安装说明；
- `02_code/r/inst/docs/INSTALL_DEPENDENCIES*.md` 去掉 GUI 依赖行；
- `04_results/README.md`、`02_code/shared/docs/output_schema.md` 去掉 GUI 提法。

---

## 4. 根目录 README 重写

`README.md` / `README-CN.md` 现在只包含两节：

1. **程序介绍** —— 一段话说明 `nanoamp` 做什么，以及本仓库是 Linux 命令行发行版；
2. **安装** —— 只用 conda：
   - `conda create -n nanoamp -c conda-forge -c bioconda` 安装 `r-base`、
     `minimap2`、`samtools` 以及全部 R 依赖（`r-*` 与 `bioconductor-*`）；
   - `R CMD INSTALL 02_code/r` 安装仓库自带的 `nanoamp` 包；
   - `sh 02_code/cli/nanoamp doctor` 作为安装验证。

---

## 5. 验证

| 检查 | 结果 |
|---|---|
| `make test`（testthat） | 全部通过 |
| `make check`（`R CMD check`） | **Status: OK** |
| `sh 02_code/cli/nanoamp doctor` | 正常输出平台、依赖目录、R 包与外部工具解析结果 |
| `git status` | 除本轮改动外无残留；磁盘回收约 3.4 GB |

---

## 6. 现状

Linux 仓库现在是一个**纯命令行发行版**：

```text
README.md / README-CN.md   程序介绍 + conda 安装
00_materials/              委托、方案、工作报告（含本报告）
01_data/                   测试数据与软链接层
02_code/
  r/                       nanoamp R 包（无 GUI）
  cli/                     命令行入口与启动器
  shared/                  参数与输出契约
03_dependence/             内置 minimap2 / samtools（Linux x86_64）
04_results/                运行结果
05_builds/                 R CMD build / check 产物
Makefile
```

未完成事项：本轮只做本地提交，没有推送远端。
