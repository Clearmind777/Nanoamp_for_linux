# 03_dependence

nanoamp 随项目分发的外部工具目录。**四个支持的平台都内置了可用的
`minimap2`**，因此刚克隆下来就能直接跑方案 A / B，不需要装 conda 或任何包管理器。

## 目录结构

```text
03_dependence/
|-- README.md / README-CN.md
|-- manifest.tsv                  # 每个内置文件的版本、来源与 sha256
|-- fetch_dependencies.sh         # 刷新二进制（支持四个平台）
|-- licenses/
|   `-- minimap2-LICENSE.txt
|-- linux-x86_64/
|   |-- README.md
|   `-- bin/minimap2
|-- linux-arm64/
|   |-- README.md
|   `-- bin/minimap2
|-- macos-x86_64/
|   |-- README.md
|   `-- bin/minimap2
`-- macos-arm64/
    |-- README.md
    `-- bin/minimap2
```

所有 Windows 专属内容（windows-x86_64、windows-arm64、MSYS2 编译脚本、
R 环境脚本以及离线安装包）都放在姊妹仓库
`a_09_18_26_mapping_programs_dev_for_win`。

## 平台支持矩阵

| 平台 | 仓库内二进制 | 文件格式 | 运行时要求 |
|---|---|---|---|
| linux-x86_64 | `linux-x86_64/bin/minimap2` | ELF x86-64 | glibc >= 2.14，系统 zlib |
| linux-arm64 | `linux-arm64/bin/minimap2` | ELF AArch64 | glibc >= 2.17，系统 zlib |
| macos-x86_64 | `macos-x86_64/bin/minimap2` | Mach-O x86_64 | 仅需 macOS 系统库 |
| macos-arm64 | `macos-arm64/bin/minimap2` | Mach-O arm64 | 仅需 macOS 系统库 |

四份都是 minimap2 2.31-r1302，内置工具总体积约 2.6 MB。确切版本、下载来源与
sha256 见 `manifest.tsv`；每个平台目录下有自己的 README，含该平台的验证命令。

## 为什么二进制取自 conda-forge

上游 minimap2 只发布 Linux x86_64 预编译包，Linux arm64 和两种 macOS 架构都没有
官方构建。conda-forge 四个平台都构建，而且——这正是能够“预置”的关键——它的构建
产物**运行时不需要 conda**：

- Linux：只链接 `libm`、`libz`、`libpthread`、`libc`，glibc 基线为 2.14（x86_64）
  / 2.17（arm64）；
- macOS：只链接 `/usr/lib/libSystem.B.dylib` 加系统 zlib，后者由 dyld 共享缓存
  提供。

这两点都按平台用 `file`、ELF 的 `DT_NEEDED` 与 `otool -L` 逐条核实过；macOS
arm64 那份还额外拷到 `/tmp` 并用 `env -i` 清空环境变量执行，确认脱离 conda 也能跑。

`samtools` **故意不内置**：`Rsamtools::asBam()` 就能完成 SAM→BAM，samtools 属于
可选依赖。如果某台机器的 `PATH` 里本来就有 samtools，`use_samtools = TRUE` 仍会用它。

## nanoamp 如何查找外部工具

解析顺序：

1. 环境变量 `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`；
2. `03_dependence/<os>-<arch>/bin/<tool>`；
3. `PATH`。

`NANOAMP_DEPENDENCE_DIR` 可以指定其他 `03_dependence` 位置，适合 R 包安装后使用。

`nanoamp doctor` 会显示平台、依赖目录，以及每个工具解析到的路径和版本。内置
二进制到位且 `PATH` 里没有 conda 时，输出形如：

```text
platform: macos-arm64
dependence directory: /path/to/repo/03_dependence
  minimap2     /path/to/repo/03_dependence/macos-arm64/bin/minimap2 (2.31-r1302)
  samtools     NOT FOUND (optional; Rsamtools is used by default)
```

## R 内比对后端

`run_haplotype_analysis(..., aligner = "r")` 使用 Biostrings/pwalign 的成对比对，
不依赖任何外部二进制。它比 minimap2 慢，适合中小扩增子，也适合内置二进制与宿主
不匹配的情况（例如 glibc 过旧）。

## 获取或更新工具

```bash
bash 03_dependence/fetch_dependencies.sh                  # 当前平台
bash 03_dependence/fetch_dependencies.sh --all             # 四个平台全刷
bash 03_dependence/fetch_dependencies.sh --platform macos-arm64
```

需要 `mamba`、`micromamba` 或 `conda`，但**只用于下载**：脚本用 `CONDA_SUBDIR`
交叉下载其他平台的包，因此一台 macOS 或 Linux 机器就能刷新全部四个平台，不需要
模拟器或 Docker。下载到的 `minimap2` 会被拷进 `03_dependence/<平台>/bin/`，并打印
sha256，便于同步更新 `manifest.tsv`。

## 许可证

- minimap2：MIT（许可证文本在 `licenses/minimap2-LICENSE.txt`）。
