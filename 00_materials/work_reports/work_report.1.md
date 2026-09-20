# 工作报告 1：R 核心算法实现与功能测试

> 日期：2026-09-20
> 依据：`00_materials/programs_dev_plan_1.md`
> 范围：开发方案第 6 节的方案 A / B / C，不含 Web、GUI、R 包和 GTF 注释

---

## 1. 摘要

本轮完成了三件事：

1. 用 R 实现了纳米孔 PCR 产物分析的三种核心算法：
   - 方案 A：参考引导校正 + 单倍型计数（默认）
   - 方案 B：从头聚类 + 簇共识
   - 方案 C：原始 reads 精确匹配（诊断）
2. 提供了两个入口：
   - RStudio 交互脚本：`02_code/scripts/run_analysis.R`
   - Rscript 命令行：`02_code/scripts/nanoamp.R call|batch|doctor`
3. 整理了三组有 FASTQ 的测试数据，生成 `01_data/ln_test_data` 软链接与 manifest，并完成功能测试。

功能测试共执行 **168 次运行**（3 种模式 × 56 组“样本 × 参考”组合），**0 次失败**。

核心结论：

- 方案 A 在 23 个有公司变异表的样本上，覆盖了公司报告的 **163 / 167 个频率 ≥5% 的变异（97.6%）**，其中 **22 / 23 个样本达到 100% 位置与等位基因重合**。
- SNV 频率与公司结果高度一致：匹配到的 15 个 SNV，频率绝对差中位数 **1.56 个百分点**，全部在 5 个百分点以内。
- 缺失（indel）因为公司按“逐碱基缺失”记录、我们按“最大缺失区段”记录，频率口径不同；按区段对比时 12/12 命中（以 E4-9 为例），但逐碱基频率差中位数为 7.67 个百分点。
- 原始 reads 精确匹配比例（方案 C）中位数只有 **12.0%**，再次验证了不能直接对原始 reads 做精确计数。

---

## 2. 交付物

| 路径 | 内容 |
|---|---|
| `02_code/R/` | R 核心库：IO、比对、变异发现、校正、聚类、精确匹配、单倍型统计 |
| `02_code/scripts/run_analysis.R` | RStudio 交互版入口 |
| `02_code/scripts/nanoamp.R` | Rscript 命令行入口（call / batch / doctor） |
| `02_code/scripts/prepare_test_data.R` | 测试数据软链接与 manifest 生成脚本 |
| `02_code/tests/testthat/` | 单元测试 |
| `02_code/tests/run_functional_tests.R` | 功能测试与公司结果对比 |
| `02_code/README.md` | 使用说明 |
| `01_data/ln_test_data/` | 规范化命名的测试数据软链接、manifest、每样本 meta |
| `04_results/test_run_1/` | 功能测试输出、对比表、频率一致性表（Git 忽略） |

---

## 3. 环境与依赖

| 项目 | 版本 / 状态 |
|---|---|
| R | 4.2.0 |
| Biostrings / Rsamtools / ShortRead | 已安装 |
| data.table / optparse / jsonlite / readxl | 已安装 |
| minimap2 | 2.17-r941 |
| samtools | 1.12 |
| DECIPHER | **安装失败**（3 次尝试均因 Bioconductor 下载中断） |

由于 DECIPHER 未能安装，方案 B 实际使用了 R 原生的“变异模式贪心聚类”作为后备后端，并在 `qc.tsv` 的 `clustering_method` 中记录为 `variant_matrix`。DECIPHER 代码路径已保留，只要安装成功即可自动切换。

---

## 4. 测试数据规范化

### 4.1 覆盖范围

本轮只处理有 FASTQ 的三组数据：

| 数据集 | 样本数 | 聚类结果数 | 公司变异表数 | Sanger 峰图数 |
|---|---:|---:|---:|---:|
| `TSM20260826` | 6 | 9 | 8 | 9 |
| `ZNF8` | 16（15 克隆 + WT） | 23 | 13 | 23 |
| `nano_seq` | 10 | 10 | 8 | 10 |
| 合计 | 32 | 42 | 29 | 42 |

最终在 `01_data/ln_test_data` 下生成 **201 个相对软链接**，未修改任何原始数据。

### 4.2 命名规范

每个样本一个目录：`01_data/ln_test_data/<dataset>/<sample>/`

固定角色文件名：

| 文件名 | 角色 |
|---|---|
| `reads.fastq` | 原始 FASTQ |
| `reference.self.fa` | 公司 cluster 1 主导共识 |
| `reference.wt.fa` | 独立对照参考（293T 或 WT） |
| `consensus.N.fa` | 第 N 个聚类共识 |
| `variants.N.xlsx` | 第 N 个公司变异统计表 |
| `sanger.N.ab1` | 第 N 个 Sanger 峰图 |
| `meta.tsv` | 该样本的角色索引 |

独立参考映射规则：

- TSM E4 系列 → `293T-E4` 共识；
- TSM G2-1-9 → `293T-G2` 共识；
- nano_seq G1–G5 → 对应 `293T-Gn` 共识；
- ZNF8 全部克隆 → WT 共识。

顶层 `manifest.tsv` 记录 `dataset`、`sample`、`role`、`cluster`、`link_path`、`target_path`、`source_note`。

---

## 5. 核心算法实现

### 5.1 方案 A：参考引导校正 + 单倍型计数

流程：

1. `minimap2 -ax map-ont --cs` 比对到参考；
2. 过滤 secondary / supplementary / 未比对 reads；
3. 按 identity 和参考覆盖度过滤；
4. 解析 `cs` tag，得到每条 read 相对参考的 SNV / 插入 / 缺失；
5. 聚合候选变异，按 `min_reads`、`min_freq`、链偏好、homopolymer 规则过滤；
6. **缺失区段归一化**：把低复杂度 / 重复区中被比对器打散、错位的小缺失合并为规范缺失区段；
7. 对每条 read，只保留通过过滤的真实变异，其余差异视为测序错误校正回参考；
8. 按校正后的序列完全一致分组，统计 reads 数、比例和置信区间。

默认参数：`min_reads=3`、`min_freq=0.02`、`min_identity=0.90`、`min_ref_coverage=0.90`、`homopolymer=4`、`strand_bias=0.90`。

### 5.2 方案 B：从头聚类 + 簇共识

流程：

1. 比对仅用于统一方向和确定参考坐标；
2. 重建每条 read 在参考区段上的序列（保留其全部差异，不做频率过滤）；
3. 优先用 `DECIPHER::DistanceMatrix + IdClusters` 聚类；
4. DECIPHER 不可用时，使用“变异模式稀疏矩阵 + 贪心聚类”后备方案；
5. 每个簇默认用 medoid 作为共识；
6. 对通过最小簇大小的簇，用 `pairwiseAlignment` 描述其相对参考的差异。

### 5.3 方案 C：原始 reads 精确匹配

统计原始 reads 与参考正链或反向互补链完全一致的条数，同时给出“包含完整参考序列”的辅助指标和原始唯一序列排行榜。该模式只用于诊断，不用于定量。

### 5.4 输出

每次运行输出：

```text
haplotypes.tsv       单倍型排名 / reads 数 / 比例 / 置信区间 / 变异描述
haplotypes.fasta     前 n 条单倍型序列
variants.tsv         候选变异表（方案 A 列名兼容公司 *.var.xls）
qc.tsv               比对率、identity、覆盖度、单倍型数等
run_manifest.json    参数、参考序列、版本、输入 MD5
alignments.bam(.bai) 中间比对文件（可关闭）
```

---

## 6. 功能测试结果

测试命令：

```bash
Rscript 02_code/tests/run_functional_tests.R \
  --outdir 04_results/test_run_1 \
  --modes A,B,C --top-n 20 --threads 4
```

### 6.1 总体结果

| 模式 | 运行数 | 成功 | 失败 | top1 平均比例 | 与公司变异平均重合率 | 平均耗时 |
|---|---:|---:|---:|---:|---:|---:|
| A | 56 | 56 | 0 | 0.6748 | 0.9807 | 0.82 s |
| B | 56 | 56 | 0 | 0.8663 | 0.3771 | 1.55 s |
| C | 56 | 56 | 0 | 0.1231 | 0（不输出变异） | 0.17 s |

### 6.2 方案 A 与公司结果对比

在 23 个“self 参考 + 公司变异表”的样本上：

- 公司报告频率 ≥5% 的变异共 **167 个**；
- 方案 A 命中 **163 个**，总体召回率 **97.6%**；
- **22 / 23 个样本达到 100% 位置与等位基因重合**；
- 唯一低于 100% 的是 `ZNF8/clone_3`，命中 5 / 9（55.6%），该样本同时存在低比对率问题，需要进一步排查。

### 6.3 频率一致性

| 变异类型 | 匹配数 | 频率绝对差中位数 | ≤5 个百分点 | ≤10 个百分点 |
|---|---:|---:|---:|---:|
| SNV | 15 | **1.56 pp** | 15 / 15（100%） | 15 / 15（100%） |
| 缺失 | 125 | 7.67 pp | 49 / 125（39.2%） | 78 / 125（62.4%） |
| 插入 | 1 | 5.73 pp | 0 / 1 | 1 / 1 |

SNV 频率与公司结果高度一致。

缺失的差异主要来自表示口径：

- 公司把一段连续缺失拆成多个“逐碱基缺失”，每个碱基单独给频率；
- 我们的方案 A 把同一段缺失合并为一个“缺失区段”，只给区段级别的频率；
- 对 E4-9 这种 14 bp 缺失，我们的区段频率 51.25%，公司逐碱基频率 50.5%–53.8%，本质上是一致的，但逐碱基对比会产生几个百分点的差。

### 6.4 方案 C：原始精确匹配

原始 reads 与参考完全一致（正链或反链）的比例：

- 最小值：2.43%
- 中位数：12.0%
- 平均值：12.31%
- 最大值：30.23%

这再次说明：**直接把原始 reads 做精确匹配会严重低估目标序列比例**，必须做校正或聚类。

### 6.5 比对率

方案 A/B 的比对率：

- 中位数 82.0%
- 平均 80.2%
- 最低 1.68%

有 **10 / 168 次运行** 的比对率低于 50%。低比对率样本包括：

| 样本 | 参考 | 使用 reads / 总 reads | 比对率 |
|---|---|---:|---:|
| `ZNF8/clone_11` | WT | 2 / 119 | 1.7% |
| `ZNF8/clone_11` | self | 25 / 119 | 24.4% |
| `TSM20260826/G2-1-9` | self / WT | 45 / 149 | 34.2% |
| `TSM20260826/293T-G2` | self | 79 / 184 | 45.7% |

原因是这些样本的 reads 与所给参考差异较大，或样本本身包含多个差异较大的簇；用单一共识作为参考会丢掉另一类单倍型的 reads。这是下一阶段需要重点改进的问题。

---

## 7. 典型案例

### 7.1 E4-3：公司位点频率 vs 我们的单倍型组成

公司结果：

| 位点 | 类型 | 频率 |
|---|---|---:|
| 135 C>T | SNP | 30.83% |
| 218 G>- | Indel | 63.61% |

方案 A 结果（self 参考）：

| 排名 | 单倍型 | reads | 比例 |
|---:|---|---:|---:|
| 1 | `218delG` | 142 | 33.33% |
| 2 | 参考序列 | 134 | 31.46% |
| 3 | `218delG;135C>T` | 114 | 26.76% |
| 4 | `135C>T` | 16 | 3.76% |
| 5 | `218delG;134insT;136C>T` | 6 | 1.41% |

聚合后：

- 135 C>T 总比例 **31.22%**，公司 30.83%；
- 218 delG 总比例 **63.15%**，公司 63.61%。

更重要的是，公司只给了两个独立位点的频率，而我们的工具进一步给出了它们的**联合单倍型组成**：

- 只有 218delG：33.33%；
- 只有 135C>T：3.76%；
- 两个变异同时存在：26.76%；
- 都不存在：31.46%。

这正是教授想要的“PCR 产物里有哪些序列、各占多少”的信息。

### 7.2 E4-9：低复杂度重复区缺失

公司报告：

- 135 C>T：41.25%；
- 219–232 区域的逐碱基缺失：约 50.5%–53.8%。

方案 A 结果：

- 135 C>T：41.00%；
- `219delGGGAAACAATGGAG`：51.25%。

单倍型组成：

| 单倍型 | 比例 |
|---|---:|
| 参考序列 | 46.81% |
| `219delGGGAAACAATGGAG;135C>T` | 39.06% |
| `219delGGGAAACAATGGAG` | 8.31% |
| `219delGGGAAACAATGGAG;134insT;136C>T` | 3.88% |
| `135C>T` | 1.94% |

这个案例也暴露并验证了缺失区段归一化的必要性：归一化前，14 bp 缺失被 minimap2 拆成多种错位的小缺失，无法形成候选；归一化后正确恢复为一个 14 bp 缺失区段。

---

## 8. 开发过程中发现并修复的问题

| 问题 | 现象 | 修复 |
|---|---|---|
| homopolymer 判定遗漏 indel 锚点 | 位于重复区边界的插入未被过滤 | 对插入同时检查锚点前一位和后一位 |
| 合成测试参考序列未命名 | `samtools`/`Rsamtools` 报空 seqlevel | 测试夹具显式命名参考序列 |
| 功能测试 `get_role` 变量名遮蔽 | 所有角色都取到 `consensus.1.fa` | 函数参数改名，避免与 data.table 列名冲突 |
| 方案 B 对所有小簇做差异注释 | 大量小簇导致不必要的 `pairwiseAlignment` | 只对通过 `min_cluster_reads` 的簇做注释 |
| 低复杂度区缺失被打散 | E4-9 的 14 bp 缺失未检出 | 增加缺失区段归一化（`delregion`） |
| 文件系统权限位噪声 | `git status` 显示 146 个 test_data 文件被修改 | 设置仓库 `core.fileMode=false`，内容未变 |
| DECIPHER 安装失败 | 3 次下载中断 | 方案 B 自动降级为变异模式贪心聚类，并在 QC 中记录 |

---

## 9. 已知限制

1. **参考偏好**
   - 方案 A 依赖参考序列；当样本包含两个差异较大的单倍型、而参考只取其中一个时，另一类 reads 可能因 identity 或覆盖度不足被过滤。
   - 低比对率样本（clone_11、G2-1-9、293T-G2）需要改成“每簇参考”或“统一 WT 参考 + 多参考”策略。

2. **indel 表示与频率口径**
   - 我们输出“最大缺失区段”，公司输出“逐碱基缺失”；两者位置重合但频率定义不同。
   - 插入尚未做类似插入区段的归一化。

3. **方案 B 的先天限制**
   - 当前 identity cutoff 为 0.99，约等于允许 5 个差异 / 500 bp；两个真实单倍型若只差 1–2 个变异，会被错误合并。
   - DECIPHER 不可用时使用变异模式贪心聚类，结果更粗，只能作为探索性结果。

4. **比例不是分子比例**
   - 没有 UMI，输出的是 reads 层面比例；PCR 扩增偏好无法消除。

5. **多簇样本未逐簇测试**
   - 功能测试只使用 `reference.self.fa`（cluster 1）；带 `.2`、`.3` 的样本没有逐簇评估。

6. **缺少真值**
   - test_data 没有已知混合比例，无法评估单倍型比例的绝对准确度；目前只能与公司结果交叉验证。

7. **本轮不包含**
   - GTF / CDS 功能注释、HTML/PDF 报告、图表、Windows GUI、R 包、Web 服务、barcode 拆分。

8. **`delregion` 支持数近似**
   - 若一条 read 在区段内有多个拆分缺失，当前位置支持数可能重复累计；归一化后按 read + key 去重，但区域发现阶段的支持数仍是近似值。

---

## 10. 下一步建议

按优先级排序：

1. **改进多单倍型样本的参考策略**
   - 对每个聚类结果单独跑一遍（`consensus.1.fa`、`consensus.2.fa` …）；
   - 或先用未过滤 reads 做一个“统一参考”，再比较。

2. **完善 indel 归一化**
   - 用标准左对齐算法处理 SNV 之外的 indel；
   - 为插入增加区段归一化；
   - 输出同时保留“区段模式”和“逐碱基模式”，与公司格式兼容。

3. **安装并验证 DECIPHER**
   - 可在有稳定网络的机器上预先下载 `DECIPHER_2.26.0.tar.gz`，再离线安装；
   - 对比 DECIPHER 聚类与当前后备聚类的差异。

4. **构造合成数据基准**
   - 设计 3–5 个已知比例的单倍型，按不同覆盖度和错误率模拟 reads；
   - 评估单倍型恢复率和比例误差，用于校准 `min_freq`、`min_reads`、`identity_cutoff`。

5. **增加 GTF / CDS 注释**
   - 先做 CDS 配置模式，再做转录本模式；
   - 注释同义、missense、nonsense、frameshift。

6. **补齐交付形态**
   - HTML 报告和图表；
   - Python/R 可复用接口；
   - Windows GUI / exe；
   - Web 服务。

---

## 11. 复现命令

```bash
# 1. 环境检查
Rscript 02_code/scripts/nanoamp.R doctor

# 2. 生成测试数据软链接
Rscript 02_code/scripts/prepare_test_data.R

# 3. 单元测试
Rscript 02_code/tests/testthat.R

# 4. 单样本命令行分析
Rscript 02_code/scripts/nanoamp.R call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --top-n 20 \
  --outdir 04_results/demo/E4-3

# 5. 完整功能测试
Rscript 02_code/tests/run_functional_tests.R \
  --outdir 04_results/test_run_1 \
  --modes A,B,C --top-n 20 --threads 4
```

RStudio：打开项目根目录的 `nanoamp.Rproj`，编辑并运行 `02_code/scripts/run_analysis.R`。

---

## 12. Git 提交

| 提交 | 说明 |
|---|---|
| `45571f3` | chore: initialize project with test data docs and development plan |
| `87f6d9f` | chore: normalize formula delimiters in development plan |
| `7e68bc8` | feat: add R core algorithms A/B/C with CLI and RStudio entrypoints |
| `34a3411` | test: add normalized ln_test_data symlinks and manifest |
| `b53be66` | fix: normalize low-complexity deletions in mode A |

测试产物位于 `04_results/test_run_1/`，按约定不进入 Git。
