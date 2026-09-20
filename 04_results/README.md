# 04_results 运行结果目录

按交付形态分层，避免 CLI、GUI、开发测试的输出互相覆盖。

```text
04_results/
├── r/          # R 版本运行结果
│   ├── test_run_1/
│   ├── demo/
│   └── dev_*/
├── cli/        # CLI 冒烟与批量测试结果
└── gui/        # GUI 测试结果
```

约定：

- 每次运行在对应形态目录下建独立子目录；
- 分析核心输出（`haplotypes.tsv`、`variants.tsv`、`qc.tsv`）字段遵循 `02_code/shared/docs/output_schema.md`；
- 本目录内容默认不进入 Git，只保留本 README。
