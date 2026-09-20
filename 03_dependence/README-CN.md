# 03_dependence

nanoamp 随项目分发的外部工具目录（仅面向 Linux 的变体）。

## 目录结构

```text
03_dependence/
|-- README.md
|-- README-CN.md
|-- manifest.tsv
|-- fetch_dependencies.sh
|-- licenses/
|   `-- minimap2-LICENSE.txt
|-- linux-x86_64/bin/
|   |-- minimap2
|   `-- samtools          # 可选后备
|-- linux-arm64/README.md
|-- macos-x86_64/README.md
`-- macos-arm64/README.md
```

所有 Windows 专属内容（windows-x86_64、windows-arm64、MSYS2 编译脚本、
R 环境脚本以及离线安装包）都放在姊妹仓库
`a_09_18_26_mapping_programs_dev_for_win`。

## nanoamp 如何查找外部工具

解析顺序：

1. 环境变量 `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`；
2. `03_dependence/<os>-<arch>/bin/<tool>`；
3. `PATH`。

`NANOAMP_DEPENDENCE_DIR` 可以指定其他 `03_dependence` 位置，适合 R 包安装后使用。

`nanoamp doctor` 会显示平台、依赖目录，以及每个工具解析到的路径和版本。

## 平台支持矩阵

| 平台 | minimap2 | samtools | 说明 |
|---|---|---|---|
| linux-x86_64 | 已内置 2.31 | 已内置 1.12（可选） | 默认用 Rsamtools 做 SAM→BAM；只有 `use_samtools = TRUE` 才调用 samtools |
| linux-arm64 | 未内置 | 未内置 | 用 conda 或源码编译；可用 R 内后端 |
| macos-x86_64 | 未内置 | 未内置 | 用 conda |
| macos-arm64 | 未内置 | 未内置 | 用 conda |

这里不再列出 Windows：`windows-x86_64` / `windows-arm64` 由姊妹仓库
`a_09_18_26_mapping_programs_dev_for_win` 维护，它自带静态链接的
minimap2 二进制。

上游事实：

- minimap2 只发布 Linux x86_64 预编译包；Linux ARM64 和 macOS 没有官方
  二进制，通常用 conda 或源码编译；
- samtools 只发布源码；conda-forge / bioconda 提供 Linux 和 macOS 版本，
  因此这些平台上用 conda 即可安装。

## R 内比对后端

`run_haplotype_analysis(..., aligner = "r")` 使用 Biostrings 的成对比对，
不依赖任何外部二进制。它比 minimap2 慢，适合中小扩增子，以及 Linux ARM64、
macOS 这类没有内置 minimap2 二进制的平台。

Linux x86_64 默认使用 `aligner = "minimap2"`。

samtools 不再是必需依赖：`Rsamtools::asBam()` 可以把 minimap2 的 SAM 转成 BAM。
只有显式设置 `use_samtools = TRUE` 才会走 samtools。

## 获取或更新工具

```bash
bash 03_dependence/fetch_dependencies.sh
```

脚本会下载官方 minimap2 Linux x86_64 二进制，并打印 Linux ARM64、macOS
的获取说明。

## 许可证

- minimap2：MIT；
- samtools：MIT/Expat。

内置 minimap2 的许可证文本位于 `licenses/`。
