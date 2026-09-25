# 输出文件 schema（跨语言契约）

所有实现（R 核心库、CLI）都应在 `--outdir` 下生成以下文件，字段名保持一致。

## haplotypes.tsv

方案 A / B：

| 列名 | 类型 | 说明 |
|---|---|---|
| `rank` | int | 按支持 reads 数排名 |
| `haplotype_id` / `cluster_id` | string / int | 单倍型或簇编号 |
| `count` | int | 支持 reads 数 |
| `proportion` | float | 占比，0–1 |
| `ci_low` / `ci_high` | float | 比例的 95% Wilson 置信区间 |
| `is_reference` | bool / NA | 是否与参考序列一致 |
| `n_snv` / `n_ins` / `n_del` | int / NA | 变异数量 |
| `length` | int | 单倍型长度 |
| `variants` | string | 变异描述，多条用 `;` 分隔；`.` 表示无变异 |

方案 C：

| 列名 | 类型 | 说明 |
|---|---|---|
| `rank` | int | 按原始序列出现次数排名 |
| `haplotype_id` | string | H1、H2… |
| `count` | int | 出现次数 |
| `proportion` | float | 占比 |
| `is_reference` | bool | 是否等于参考正链或反链 |
| `length` | int | 序列长度 |
| `sequence` | string | 原始序列 |

## haplotypes.fasta

- 方案 A/B：前 `top_n` 条单倍型/簇共识序列；
- 方案 C：前 `top_n` 条原始序列；
- header 建议：`H<rank>_<variant_summary>` 或 `C<cluster_id>_<variant_summary>`。

## variants.tsv

方案 A 列名与公司 `*.var.xls` 兼容：

```text
Chr  Pos  Ref  Alt  DP  Ref_dp  Alt_dp  Freq  DP4  Seq  Filter_Status  Filter_Reason
```

- `Ref` / `Alt` 中的 `-` 表示插入/缺失；
- `Freq` 为 0–1 的小数，公司表为百分比时需除以 100；
- `Filter_Status` 取值 `PASS` / `FILTERED`。

方案 B 的 `variants.tsv` 至少包含：

```text
cluster_id  count  type  pos  ref  alt  Seq
```

## qc.tsv

两列 `metric` / `value`，至少包含：

```text
mode
reference_label
reference_length
n_reads_total
n_reads_primary
n_reads_used
mapping_rate
mean_identity
mean_coverage
n_haplotypes / n_clusters
top1_proportion
top1_is_reference
```

方案 A 额外包含 `aligner`、`n_raw_variants`、`n_pass_variants`、`exact_reference_proportion`。方案 B 额外包含 `aligner`、`identity_cutoff`、`clustering_method`、`consensus_method`、`decipher_version`。

## run_manifest.json

记录：

```text
nanoamp_version
mode
timestamp
r_version / python_version
reference: {name, length, md5, path}
params
qc
reads_md5
```

## annotation.tsv（功能注释，可选）

仅当传入 `--annotate-config` 时生成。每个**单倍型 × 所选转录本**一行；
`--transcript all` 时包含全部重叠转录本。

| 列名 | 类型 | 说明 |
|---|---|---|
| `rank` | int | 行序号（按 reads 数降序） |
| `haplotype_id` | string | 关联 `haplotypes.tsv` |
| `count` / `proportion` | int / float | 从 `haplotypes.tsv` 带过来，便于直接阅读 |
| `transcript_id` / `transcript_name` | string | 所用转录本 |
| `is_mane` / `is_canonical` | bool | 该转录本是否 MANE Select / Ensembl canonical |
| `cds_ok` | bool | FALSE 表示边界或序列异常，后续列为空 |
| `ref_protein_length` / `alt_protein_length` | int | 参考/突变蛋白长度（aa） |
| `n_aa_changed` | int | 氨基酸改变数 |
| `protein_change` | string | HGVS 风格描述（**非合规 HGVS**），如 `p.Lys2Glu`、`p.Phe3fs`、`p.Lys2del` |
| `consequence_en` / `consequence_zh` | string | 后果英文枚举与中文标签（中英双列） |
| `consequence_any_transcript` / `_zh` | string | 该单倍型在所选转录本中**最严重**的后果 |
| `transcript_conflict` | bool | 同一单倍型在不同转录本下后果不同 |
| `variants` / `signature` | string | 与 `haplotypes.tsv` 一致 |
| `notes` | string | 异常说明，例如 `length change +14 bp (not a multiple of 3)` |

### 后果枚举（`consequence_en`）

```text
frameshift  stop_gained  stop_lost  start_lost
inframe_insertion  inframe_deletion  missense  synonymous
splice_region  5_prime_UTR  3_prime_UTR  intron  outside_cds
cds_boundary_disrupted  cds_ambiguous_base  no_variant
```

### qc.tsv 注释相关指标

```text
annotation_enabled  annotation_name  annotation_route  annotation_source
ensembl_release  genetic_code  n_transcripts
n_haplotypes_annotated  n_haplotypes_skipped
n_frameshift  n_stop_gained  n_stop_lost  n_start_lost
n_missense  n_synonymous  n_inframe  n_transcript_conflicts
```

### run_manifest.json 的 annotation 段

```json
"annotation": {
  "enabled": true,
  "source": "ensembl-rest",
  "ensembl_release": "116",
  "config_path": "...", "config": { },
  "genomic": { "chrom": "19", "start": 0, "end": 0, "strand": "+",
                "identity": 1.0, "n_mismatch": 0, "method": "exact_match" },
  "transcripts": [ { "transcript_id": "ENST...", "cds_length": 0,
                     "protein_length": 0, "protein_verified": true } ]
}
```

## variants_annotation.tsv（变异级明细，可选）

仅当 `--annotation-detail` 时生成：每个变异一行。

| 列名 | 说明 |
|---|---|
| `haplotype_id` | 所属单倍型；`transcript_id` 为所用转录本 |
| `type` | `snv` / `ins` / `del` / `delregion` |
| `genome_pos` | 基因组坐标（1-based） |
| `cds_pos` | 该变异在拼接后 CDS 中的位置；空表示不在 CDS 内 |
| `ref` / `alt` | 基因组正链上的等位基因（负链已翻转） |
| `codon_ref` / `codon_alt` | 受影响密码子（仅替换类变异） |
| `aa_ref` / `aa_alt` | 对应氨基酸（仅替换类变异） |
| `consequence_en` / `consequence_zh` | 单变异后果（中英双列） |

注意：这是**单变异**视角。多变异组合的最终后果以 `annotation.tsv` 为准——两者可能不同。

### 负链支持

定位到负链时，`genome_pos` 按 `end - pos + 1` 换算（插入为 `end - pos + 2`，因为插入锚定在
插入点之后），等位基因反向互补，使所有操作都能作用在正链序列上。正链与负链表述的同一变异
必须得到相同后果（由镜像测试保证）。
