# CLI 契约（跨语言）

CLI 是所有交付形态的统一入口。R 版本已实现为 `02_code/r/scripts/nanoamp.R`；Python 版本后续实现为同一命令名的等价入口。

## 命令

```text
nanoamp call   --reads <fastq> --reference <fasta> --outdir <dir> [--mode A|B|C] [选项]
nanoamp batch  --sample-sheet <tsv> --outdir <dir> [--mode A|B|C] [选项]
nanoamp doctor
```

## call 选项

| 选项 | 类型 | 默认值 | 说明 |
|---|---:|---:|---|
| `--reads` | path | 必填 | 输入 FASTQ（可 .gz） |
| `--reference` | path | 必填 | 目的序列 FASTA |
| `--outdir` | path | 必填 | 输出目录 |
| `--mode` | string | `A` | A 参考引导 / B 从头聚类 / C 原始精确匹配 |
| `--top-n` | int | 20 | 输出前 n 条单倍型 |
| `--min-reads` | int | 3 | 变异最低支持 reads 数 |
| `--min-freq` | float | 0.02 | 变异最低频率 |
| `--min-identity` | float | 0.90 | read 最低 identity |
| `--identity-cutoff` | float | 0.99 | 方案 B 聚类 identity 阈值 |
| `--min-cluster-reads` | int | 2 | 方案 B 最小簇大小 |
| `--consensus-method` | string | `decipher` | `decipher` 或 `medoid` |
| `--threads` | int | 4 | 线程数 |
| `--ref-label` | string | 参考名 | 参考标签 |
| `--no-intermediates` | flag | false | 不保留 BAM 等中间文件 |

## batch 输入表

TSV，至少包含：

```text
sample	reads	reference
```

可选列：`ref_label`、`outdir`。

## 输出

每次 `call` 在 `--outdir` 下生成 `haplotypes.tsv`、`haplotypes.fasta`、`variants.tsv`、`qc.tsv`、`run_manifest.json`；字段定义见 `02_code/shared/docs/output_schema.md`。

## 退出码

| 退出码 | 含义 |
|---:|---|
| 0 | 成功 |
| 1 | 参数错误 |
| 2 | 输入文件缺失或格式错误 |
| 3 | 外部依赖缺失（minimap2 / samtools / DECIPHER） |
| 4 | 分析过程失败 |
