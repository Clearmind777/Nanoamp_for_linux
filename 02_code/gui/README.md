# Windows GUI（待开发）

GUI 的目标用户是教授和实验人员，原则是“选两个文件、点一个按钮、看结果表”。

## 计划

- 技术栈：PySide6（Qt）；
- 调用方式：调用 Python 核心库或 `02_code/cli` 的统一 CLI，不重复实现算法；
- 打包：PyInstaller `--onedir` + NSIS 安装包；
- 随包提供 Windows 版 `minimap2`，避免用户单独安装。

## 界面要素

- 测序文件选择（FASTQ / FASTQ.GZ）；
- 目的序列选择（FASTA）；
- 输出目录选择；
- 模式选择：参考引导（默认）/ 从头聚类 / 精确匹配；
- 参数：`top-n`、最低频率、线程数；
- 运行按钮、进度条、日志窗口；
- 结果表：排名、序列、reads 数、比例、是否与参考一致、变异描述；
- 导出：TSV / Excel / FASTA；可选打开 HTML 报告；
- 批处理：选择文件夹，自动识别 FASTQ，生成汇总表。

## 前置条件

1. Python 核心库完成；
2. CLI 契约稳定（见 `02_code/cli/README.md`）；
3. PyInstaller + pysam + minimap2 打包验证通过。
