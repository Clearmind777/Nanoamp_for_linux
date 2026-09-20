# nanoamp R 实现（v0.2）

纳米孔 PCR 产物单倍型分析的 R 实现，对应开发方案第 6 节的三种算法：

- **方案 A**：参考引导校正 + 单倍型计数（默认，推荐定量）
- **方案 B**：DECIPHER 聚类 + 簇共识（探索性）
- **方案 C**：原始 reads 精确匹配（诊断）

跨语言参数与输出契约见 `02_code/shared/`。

## 目录

```text
02_code/r/
├── R/                      # 核心算法模块
├── scripts/
│   ├── run_analysis.R      # RStudio 交互入口
│   └── nanoamp.R           # Rscript CLI
├── tests/
│   ├── testthat.R
│   ├── testthat/test-core.R
│   └── run_functional_tests.R
├── tools/prepare_test_data.R
├── config/default_params.R
└── nanoamp.Rproj
```

## 环境要求

- R >= 4.2
- R 包：`Biostrings`、`Rsamtools`、`ShortRead`、`data.table`、`optparse`、`jsonlite`、`readxl`
- 外部命令：`minimap2`、`samtools`
- 方案 B 推荐：`DECIPHER`（2.26.0 已验证）

```bash
Rscript 02_code/r/scripts/nanoamp.R doctor
```

## 快速开始

### RStudio

1. 打开 `02_code/r/nanoamp.Rproj`；
2. 编辑 `02_code/r/scripts/run_analysis.R` 顶部的 `CONFIG`；
3. 运行整个脚本。脚本会自动向上寻找项目根目录。

### 命令行

```bash
# 单样本
Rscript 02_code/r/scripts/nanoamp.R call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --top-n 20 \
  --outdir 04_results/r/demo/E4-3

# 方案 B（DECIPHER）
Rscript 02_code/r/scripts/nanoamp.R call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode B --consensus-method decipher \
  --outdir 04_results/r/demo/E4-3_modeB

# 批处理
Rscript 02_code/r/scripts/nanoamp.R batch \
  --sample-sheet samples.tsv --mode A --outdir 04_results/r/batch
```

### 测试

```bash
# 生成软链接测试数据
Rscript 02_code/r/tools/prepare_test_data.R

# 单元测试
Rscript 02_code/r/tests/testthat.R

# 功能测试
Rscript 02_code/r/tests/run_functional_tests.R \
  --outdir 04_results/r/test_run_1 --modes A,B,C --threads 4
```

## 方案 B：DECIPHER 实现

流程：

1. 比对到参考，统一方向并截取扩增子区段；
2. 重建每条 read 的序列（保留全部差异，不做频率过滤）；
3. `DECIPHER::DistanceMatrix` 计算序列距离；
4. `DECIPHER::Clusterize` 按 `identity_cutoff`（默认 0.99）聚类；
5. 每个簇用 `DECIPHER::AlignSeqs` 做多序列比对，再用多数投票生成无 gap 共识；
6. 大簇超过 `max_msa_seqs`（默认 100）时，保留 medoid 并系统抽样后再比对；
7. 对通过 `min_cluster_reads` 的簇，用 `pairwiseAlignment` 描述其相对参考的差异。

若 DECIPHER 不可用，自动降级为“变异模式贪心聚类”，并在 `qc.tsv` 的 `clustering_method` 中记录。

## 输出

| 文件 | 说明 |
|---|---|
| `haplotypes.tsv` | 单倍型排名、reads 数、比例、置信区间、变异描述 |
| `haplotypes.fasta` | 前 n 条单倍型序列 |
| `variants.tsv` | 候选变异表；方案 A 列名兼容公司 `*.var.xls` |
| `qc.tsv` | reads 数、比对率、identity、覆盖度、聚类/共识方法 |
| `run_manifest.json` | 参数、参考序列、版本、输入文件 MD5 |
| `alignments.bam(.bai)` | 方案 A/B 中间比对文件（可选保留） |
