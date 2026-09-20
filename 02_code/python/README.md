# Python 实现（待开发）

目录已预留，目标是与 R 版本共用同一套参数和输出 schema。

## 规划

```text
python/
├── pyproject.toml
├── src/nanoamp/
│   ├── __init__.py
│   ├── cli.py
│   ├── io.py
│   ├── align.py
│   ├── variants.py
│   ├── haplotype.py
│   └── annotate.py
└── tests/
```

## 计划依赖

- `pysam`：BAM 解析；
- `mappy` 或外部 `minimap2`：比对；
- `biopython`：FASTA / FASTQ / 翻译；
- `numpy` / `pandas`：统计与表格；
- `typer` 或 `click`：CLI；
- 与 R 版本共用 `02_code/shared/params/default_params.json` 和 `02_code/shared/docs/output_schema.md`。

## 开发要求

1. 先实现方案 A，再实现 B/C；
2. 与 R 版本在同一测试集上输出一致的 `haplotypes.tsv` 和 `variants.tsv`；
3. `02_code/tests/` 下增加 R/Python 结果一致性测试。
