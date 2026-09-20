# 03_dependence

nanoamp 随项目分发的外部工具目录。

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
|-- windows-x86_64/
|   |-- README.md
|   |-- install_msys2_toolchain.ps1   # 可复现的编译链安装脚本
|   |-- build_minimap2.sh             # 从源码编译 minimap2.exe
|   `-- bin/minimap2.exe              # 仓库内编译，静态链接
|-- linux-arm64/README.md
|-- windows-arm64/README.md
|-- macos-x86_64/README.md
`-- macos-arm64/README.md
```

## nanoamp 如何查找外部工具

解析顺序：

1. 环境变量 `NANOAMP_MINIMAP2` / `NANOAMP_SAMTOOLS`；
2. `03_dependence/<os>-<arch>/bin/<tool>`（Windows 下为 `<tool>.exe`）；
3. `PATH`。

`NANOAMP_DEPENDENCE_DIR` 可以指定其他 `03_dependence` 位置，适合 R 包安装后使用。

`nanoamp doctor` 会显示平台、依赖目录，以及每个工具解析到的路径和版本。

## 平台支持矩阵

| 平台 | minimap2 | samtools | 说明 |
|---|---|---|---|
| linux-x86_64 | 已内置 2.31 | 已内置 1.12（可选） | 默认用 Rsamtools 做 SAM→BAM；只有 `use_samtools = TRUE` 才调用 samtools |
| windows-x86_64 | 已内置 2.31（仓库内编译） | 未内置 | 静态链接，无需 MSYS2 / Cygwin / conda / WSL；samtools 不需要，Rsamtools 已覆盖 |
| linux-arm64 | 未内置 | 未内置 | 用 conda 或源码编译；可用 R 内后端 |
| windows-arm64 | 无二进制 | 无二进制 | 用 R 内后端，或跑 x86_64 版本（模拟） |
| macos-x86_64 | 未内置 | 未内置 | 用 conda |
| macos-arm64 | 未内置 | 未内置 | 用 conda |

上游事实：

- minimap2 只发布 Linux x86_64 预编译包，没有**官方** Windows / ARM 二进制；
  但源码可以用 MSYS2 MINGW-w64 工具链在 Windows 上原生编译 —— 本仓库的
  `windows-x86_64/bin/minimap2.exe` 就是这么来的。
- samtools 只发布源码，没有官方 Windows 二进制；htslib 官方 INSTALL 文档明确
  推荐 Windows 用 MSYS2/MINGW64 编译。
- conda-forge / bioconda 提供 Linux ARM64 的 samtools，但不提供 Windows 版本；
  bioconda 本身不支持 Windows。

## Windows 源码编译

Windows 上不需要 conda，也不需要 WSL，两步即可：

```powershell
# 1. 便携式 MSYS2 + MINGW-w64 工具链（约 1.5 GB，位于仓库之外）
pwsh -File 03_dependence/windows-x86_64/install_msys2_toolchain.ps1

# 2. 编译并安装 minimap2.exe
bash 03_dependence/windows-x86_64/build_minimap2.sh
```

工具链体积过大，不纳入仓库；仓库保留上述两个脚本、编译产物及其来源信息。
固定版本、编译参数和哈希见 `windows-x86_64/README.md`。

## R 内比对后端

`run_haplotype_analysis(..., aligner = "r")` 使用 Biostrings 的成对比对，
不依赖任何外部二进制。它比 minimap2 慢，适合中小扩增子，以及 Windows、ARM
这类没有 minimap2 二进制的平台。

Linux x86_64 默认使用 `aligner = "minimap2"`。

samtools 不再是必需依赖：`Rsamtools::asBam()` 可以把 minimap2 的 SAM 转成 BAM。
只有显式设置 `use_samtools = TRUE` 才会走 samtools。

## 获取或更新工具

```bash
bash 03_dependence/fetch_dependencies.sh
```

脚本会下载官方 minimap2 Linux x86_64 二进制，并打印 Linux ARM64、Windows、
macOS 的获取说明。

## 许可证

- minimap2：MIT；
- samtools：MIT/Expat。

内置 minimap2 的许可证文本位于 `licenses/`。
