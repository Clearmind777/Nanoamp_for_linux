# 纳米孔 PCR 产物分析程序开发方案 v1

> 依据文档：`00_materials/programs_dev_info.md`
> 依据数据：`01_data/test_data/`（约 408 个文件，约 81 MB）
> 文档状态：第 1 版方案，供讨论和确认
> 暂定名称：`nanopore_amplicon`，命令行简称 `nanoamp`（名称可改）

---

## 1. 委托解读

### 1.1 委托原话拆解

委托方是一位不太懂生信的生物学教授，核心诉求可以拆成下面几点：

1. 现在有公司提供“纳米孔测序 PCR 产物”的服务，交付的是 FASTQ 等测序数据，但不提供配套分析软件。
2. 教授的理论假设是：纳米孔测序能拿到每一条序列的准确信息。
3. 每个小文库都让生信同学手工分析，数量太多，不可持续。
4. 需要一个自动化的小程序，输入是：
   - 测序 FASTQ 文件；
   - 目的序列（目标参考序列）。
5. 输出是：
   - 数量 / 比例排名前 n 的详细序列，n 可自定义；
   - 每条序列的数量；
   - 每条序列占总 reads 的比例。
6. 可选功能：
   - 连接 GTF 等注释信息；
   - 判断变异属于移码、提前终止、missense 等。
7. 最终要回答的业务问题：
   - PCR 产物中，有多少序列和想要的序列**完全一样**？
   - 不一样的序列长什么样？
   - 两类序列各占多少比例？

### 1.2 真正要解决的问题

这个程序本质上不是“做一个 FASTA 去重脚本”，而是一个**扩增子单倍型（haplotype）定量工具**。它需要同时解决三件事：

1. **区分真实序列差异和测序错误**
   - 纳米孔 reads 有错误，原始 reads 不能直接拿来“完全相同”计数。
   - 必须先把 reads 校正、聚类或构建共识序列，再统计“序列类型”。

2. **定量每种序列的比例**
   - 输出每个单倍型的 reads 数和百分比。
   - 由于没有 UMI，比例只能是“reads 层面的估计”，不是绝对分子数，需要明确说明。

3. **把序列差异翻译成生物学结论**
   - 是 SNP、插入、缺失，还是多个变异的组合？
   - 是否导致移码、提前终止、missense、同义突变？
   - 是否位于剪接位点、UTR、内含子？

### 1.3 你提出的四个交付形态

你在 `programs_dev_info.md` 第 2 节提出的最终形态：

| 形态 | 目标用户 | 关键需求 |
|---|---|---|
| Windows GUI `.exe` | 教授本人、不写代码的实验人员 | 双击即可用，选择文件、填参数、看结果、导出表格 |
| R / Python 终端脚本 | 会一点编程的组内同学 | 命令行调用，支持批处理和参数化 |
| R 包 / Python 模块 | 生信同学、开发者 | 可被其他流程调用，自由度更高 |
| 远程 Web 服务 | 全实验室、跨电脑使用 | 浏览器上传 FASTQ，服务器分析，网页看结果和下载 |

这四个形态不应该写成四套程序，而应该共用同一个分析核心，外层做不同的“壳”。这是本方案最重要的架构决策。

### 1.4 边界说明

本方案聚焦“PCR 产物 / 扩增子”的分析，不做以下事情：

- 不做全基因组、宏基因组、转录组组装；
- 不做 basecalling（默认输入已经 basecall 过的 FASTQ）；
- 不替代公司交付的 Sanger 验证；
- 不在第一版处理复杂结构变异、融合基因、线粒体异质性专用模型；
- 第一版不追求绝对定量，只做 reads 层面的相对定量。

---

## 2. 从 test_data 得到的实证结论

### 2.1 数据组成

test_data 里共有五组数据，覆盖了不同批次、不同公司和不同目录组织方式：

| 目录 | 样本数 | 数据类型 | 特点 |
|---|---:|---|---|
| `SD260728184122_1` | 3 | 纳米孔 + Sanger | 结构化交付，ZAK / GCN2 靶点 |
| `SD260812174403_1` | 15 | 纳米孔 + Sanger | 结构化交付，A4 / E4 两组，深度差异大 |
| `TSM20260826-020-01254` | 6 | 纳米孔 + Sanger | 平铺输出，含 293T 对照 |
| `ZNF8` | 15 + 1 WT | 纳米孔 + Sanger | ZNF8 靶点，含 WT 对照和质粒图谱 |
| `nano_seq` | 10 | 纳米孔 + Sanger | G1–G5 与 293T-G1–G5 对照 |

这些数据正好可以作为程序开发的第一批测试集。

### 2.2 关键实证：原始 reads 不能直接精确计数

这是整个方案中最重要的技术结论。我抽取了四个代表性 BAM，统计每条 read 与该公司共识序列的差异（用 `NM` 标签 / read 长度估算 identity），结果如下：

| 数据集 | 样本 | reads 数 | 平均 identity | 完全匹配（NM=0）的 reads 比例 | 平均每条 read 的差异数 |
|---|---|---:|---:|---:|---:|
| TSM | `E4-3` | 360 | 99.62% | 12.2% | 2.00 |
| nano_seq | `G3` | 205 | 99.45% | 2.4% | 4.06 |
| ZNF8 | 克隆 `4` | 80 | 99.27% | 73.8% | 2.33 |
| SD260812 | `G22608076105` | 13,897 | 98.81% | 3.8% | 6.22 |

怎么理解这张表：

- 这些 reads 已经比普通 1D 纳米孔 reads 干净（identity 98.8%–99.6%），但**仍然不是逐条准确**。
- 在 SD 数据中，13,897 条 reads 里只有 531 条（3.8%）和共识序列完全一致。
- 如果直接用“read 是否和参考完全相同”来统计“有多少是想要的序列”，会把绝大多数 reads 误判成“不一样”。
- ZNF8 克隆 4 的完全匹配率高达 73.8%，主要因为它的序列短（约 208–320 bp）；这反而说明**读长越小、错误越少**，不能用单一阈值套所有数据。

结论：**必须做错误校正 / 聚类 / 共识序列构建，不能做原始 reads 的精确匹配计数。**

### 2.3 关键实证：公司现有流程就是“聚类 + 共识 + 变异检测”

从 BAM 头和文件名可以看到，公司交付的分析流程是：

```text
clean.fastq
  → 按 barcode 拆分
  → reads 聚类（Clust_0、Clust_1 ...）
  → 每个簇生成共识序列（*.seq）
  → 把该簇 reads 比对回共识序列
  → 统计少数变异（*.变异统计表.xlsx）
  → Sanger 验证（*.ab1）
```

这说明我们的程序不需要从零发明分析范式，而是可以：

1. 复刻公司流程的核心步骤；
2. 把它做得更通用、可配置、可批量；
3. 输出更符合教授问题的“单倍型数量 / 比例表”；
4. 增加 GTF 功能注释；
5. 提供 GUI、R 包、Web 等易用形态。

### 2.4 需要处理的序列差异类型

从 `*.var.xls` 和 `*.变异统计表.xlsx` 观察到的变异类型：

- 单碱基替换：如 `C>T`、`G>A`；
- 单碱基插入 / 缺失；
- 多碱基插入：例如 `GTGAACCTGAAGAAAATGAGGAAAAAATA` 这类 13 bp 插入；
- 多碱基缺失；
- 同一条 read 上的多个变异组合（真正的单倍型）；
- homopolymer / poly 结构附近的假阳性插入缺失；
- 频率从几个百分点到 40% 以上的混合序列。

因此算法必须支持：

- 长插入 / 长缺失（不能只做 SNP）；
- 多个变异的相位（phasing）保持；
- homopolymer 区域特殊处理；
- 低比例单倍型的检测与过滤。

### 2.5 对设计的直接启示

| 实证结论 | 对程序的要求 |
|---|---|
| 原始 reads 错误率约 0.4%–1.2% | 必须有校正 / 聚类 / 共识步骤 |
| 公司流程是聚类 + 共识 | 支持从头聚类模式，保证结果可比 |
| 变异包含长插入缺失 | 用支持长 indel 的比对器，如 minimap2 |
| 同一 reads 有多个变异 | 保留相位，输出单倍型而不是孤立变异列表 |
| 数据深度差异大（几十到上万 reads） | 提供低深度警告和置信区间 |
| 有 293T / WT 对照 | 支持指定参照样本，区分背景变异和编辑变异 |
| 有公司 xlsx / var.xls 结果 | 输出字段尽量兼容，方便交叉验证 |

---

## 3. 产品目标与验收标准

### 3.1 功能目标

第一版（MVP）必须做到：

1. 输入一个 FASTQ（或 FASTQ.GZ）+ 一个目的序列 FASTA；
2. 自动完成 reads 比对、错误校正 / 聚类、单倍型构建；
3. 输出排名前 n 的序列，包含：
   - 序列本身；
   - reads 数；
   - 占有效 reads 总数的比例；
   - 与目的序列相比有哪些差异；
   - 是否与目的序列完全一致；
4. 输出所有检测到的候选变异位点；
5. 输出 QC 信息：reads 数、长度分布、比对率、平均 identity、覆盖度；
6. 支持中文文件名和中文路径；
7. 全程本地运行，不依赖联网。

第二版增加：

8. GTF / CDS 功能注释：同义、missense、nonsense、frameshift、in-frame indel 等；
9. 多样本批处理：一个文件夹里几十上百个 FASTQ，一次跑完；
10. Sanger / AB1 对照展示（可选）；
11. 与公司 `*.var.xls` 格式兼容的变异表输出。

### 3.2 非功能目标

- **易用性**：教授不写代码也能用；GUI 上只有必要参数，其余用默认值。
- **可重复性**：每次运行输出参数、软件版本、输入文件校验值。
- **可扩展性**：核心库与界面解耦，四个交付形态共用同一套算法。
- **可移植性**：Windows 10/11 可直接运行；Linux 服务器可部署；R / Python 可调用。
- **性能**：单样本 10^5 条 reads、1–2 kb 扩增子，普通笔记本 2 分钟内完成。
- **可解释性**：输出中明确区分“参考序列”“校正后单倍型”“原始 read 支持数”，避免误导。

### 3.3 验收标准（建议）

| 项目 | 验收标准 |
|---|---|
| 单倍型恢复 | 合成数据中，频率 ≥ 5% 的真实单倍型全部被检出 |
| 比例准确性 | 合成数据中，主要单倍型比例误差 ≤ 3–5 个百分点 |
| 与公司结果一致性 | 对公司报告的频率 ≥ 5% 的变异，位置和等位基因一致率 ≥ 95% |
| 运行速度 | 10^5 reads / 1.5 kb 扩增子 ≤ 2 分钟 |
| Windows 可用性 | 在无 Python / R 的 Windows 10/11 上，双击 exe 可完成一次分析 |
| R / Python 可用性 | `install.packages()` / `pip install` 后，三行代码完成一次分析 |
| Web 可用性 | 通过 IP:端口访问，上传 FASTQ + 参考，等待后下载结果 |
| 结果可追溯 | 输出中包含参数、版本、时间、输入文件哈希 |

具体阈值在 Phase 1 结束后根据真实数据校准。

---

## 4. 用户与使用场景

### 4.1 用户角色

| 角色 | 技术水平 | 主要诉求 | 对应交付形态 |
|---|---|---|---|
| 教授 / 实验人员 | 不懂生信 | 上传文件、点按钮、看结论 | Windows GUI、Web |
| 组内学生 | 会 R / Python 基础 | 批量跑、调参数、导结果 | CLI、R 包、Python 模块 |
| 生信同学 | 熟练 | 嵌入已有流程、二次开发 | Python 模块、CLI |
| 外部合作者 | 不等 | 浏览器上传、下载报告 | Web |

### 4.2 典型场景

**场景 A：教授自己分析一个样本**

1. 打开 Windows 程序；
2. 选择 `sample.fastq` 和 `target.fasta`；
3. n 填 20；
4. 点击“开始”；
5. 看到表格：第 1 行是目标序列，占 62%；第 2 行有一个 3 bp 缺失，占 21%；第 3 行有 SNP，占 8%……
6. 点击“导出 Excel”。

**场景 B：生信同学批量跑 96 个样本**

```bash
nanoamp batch \
  --sample-sheet samples.tsv \
  --top-n 20 \
  --outdir results/
```

输出每个样本一个子目录，加一张 `summary.tsv` 汇总表。

**场景 C：R 用户在自己流程里调用**

```r
library(nanoporeAmplicon)

res <- na_call(
  reads = "sample.fastq.gz",
  reference = "target.fasta",
  top_n = 20,
  gtf = "genes.gtf",
  transcript_id = "ENST00000xxxxx"
)

head(res$haplotypes)
```

**场景 D：实验室 Web 服务**

1. 浏览器打开 `http://服务器IP:8501`；
2. 拖入 FASTQ 和参考 FASTA；
3. 勾选“注释 GTF”、选择转录本；
4. 提交任务，页面显示进度；
5. 分析完成后在线查看表格、图表，下载 ZIP。

---

## 5. 输入输出规格

### 5.1 输入

| 输入 | 是否必需 | 说明 |
|---|---|---|
| `--reads` | 必需 | 单样本 FASTQ / FASTQ.GZ；批处理时可用 glob 或目录 |
| `--reference` | 必需 | 目的序列 FASTA，单条记录；也接受多条并自动匹配 |
| `--sample-sheet` | 批处理必需 | TSV，列：`sample`、`reads`、`reference`、可选 `gtf`、`cds_config` |
| `--gtf` | 可选 | 基因注释 GTF |
| `--genome` / `--transcript-fasta` | GTF 模式需要 | 用于把扩增子参考映射到转录本坐标 |
| `--transcript-id` | GTF 模式建议 | 指定用于注释的转录本 |
| `--cds-config` | 可选 | 更简单的 CDS 注释配置，适合只有扩增子序列的情况 |
| `--primers` | 可选 | 引物序列；用于去除引物区，避免把引物错误算成变异 |

### 5.2 主要参数

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `--top-n` | 20 | 输出前 n 条单倍型 |
| `--mode` | `reference` | `reference`（参考引导）、`de-novo`（从头聚类）、`exact`（原始精确匹配，仅诊断） |
| `--min-reads` | 3 | 候选等位基因至少需要多少条 reads 支持 |
| `--min-freq` | 0.01–0.02 | 候选等位基因最低频率，需用数据校准 |
| `--min-identity` | 0.95 | read 与参考的最低 identity，低于此值丢弃或标记 |
| `--min-coverage` | 10 | 位点最低覆盖度 |
| `--max-homopolymer` | 4 | homopolymer 长度阈值，超过则特殊过滤 |
| `--strand-bias` | 0.9 | 链偏好阈值 |
| `--threads` | 4 | 线程数 |
| `--keep-intermediates` | false | 是否保留中间 BAM、校正后 reads 等 |
| `--report` | html | 输出报告格式：`html`、`pdf`、`none` |

第一版建议把大部分参数藏在 `advanced` 里，GUI 只暴露 `top-n`、模式、最低频率。

### 5.3 输出文件

```text
outdir/
├── haplotypes.tsv          # 核心结果：前 n 条单倍型
├── haplotypes.fasta        # 前 n 条单倍型序列
├── haplotypes_all.tsv      # 所有单倍型（不截断）
├── variants.tsv            # 所有候选变异位点
├── variants_filtered.tsv   # 过滤后变异
├── variants.xls            # 与公司 *.var.xls 兼容格式（可选）
├── qc.json                 # QC 指标
├── qc_read_length.png      # read 长度分布
├── qc_coverage.png         # 覆盖度
├── report.html             # 可视化报告
├── run.log                 # 运行日志
└── run_manifest.json       # 参数、版本、输入哈希
```

### 5.4 核心输出字段

`haplotypes.tsv`：

| 列名 | 含义 |
|---|---|
| `rank` | 按 reads 数排名 |
| `haplotype_id` | 单倍型编号，如 H1、H2 |
| `count` | 支持该单倍型的 reads 数 |
| `proportion` | 占有效 reads 的比例 |
| `ci_low` / `ci_high` | 比例的 95% 置信区间（Wilson） |
| `is_reference` | 是否与目的序列完全一致 |
| `n_snv` / `n_ins` / `n_del` | 各类变异数量 |
| `length` | 单倍型长度 |
| `variants` | 变异描述，如 `c.135C>T`、`c.137delT` |
| `cds_effect` | 功能注释，如 `missense`、`frameshift`、`nonsense` |
| `protein_change` | 蛋白变化，如 `p.Ala45Val`、`p.Arg50Ter` |
| `flags` | 警告，如 `low_coverage`、`homopolymer` |

`variants.tsv` 尽量兼容公司 `*.var.xls` 的列：

```text
Chr  Pos  Ref  Alt  DP  Ref_dp  Alt_dp  Freq  DP4  Seq  Filter_Status  Filter_Reason
```

这样做的目的：

- 公司已有结果可以直接拿来对比；
- 用户不需要重新学一套字段；
- 可以用 diff 做回归测试。

### 5.5 关于“完全一样”的定义

程序里需要明确三种“一样”：

1. **raw exact match**：原始 read 与参考完全相同（受测序错误影响，通常很低）；
2. **corrected exact match**：校正后单倍型与参考完全相同（默认输出）；
3. **consensus exact match**：某个簇的共识序列与参考完全相同。

默认报告第 2 种，并在 QC 里同时给出第 1 种，帮助用户理解测序错误的影响。

---

## 6. 核心算法设计

### 6.1 问题形式化

给定：

- 一组纳米孔 reads $R = \{r_1, r_2, ..., r_n\}$；
- 一条目的序列 $T$；
- 可选注释 $A$。

求：

- 一组单倍型 $H = \{h_1, h_2, ..., h_k\}$；
- 每个 $h_j$ 的支持 reads 数 $c_j$；
- 比例 $p_j = c_j / \sum c_i$；
- 每个 $h_j$ 相对 $T$ 的差异和功能注释。

难点在于：reads 带有测序错误，不能把每个不同的 raw read 当成一个单倍型。

### 6.2 方案 A：参考引导校正 + 单倍型计数（推荐默认）

这是第一版推荐方案。它的核心思想是“用已知目的序列帮助区分真实变异和测序错误”。

步骤：

1. **reads 预处理**
   - 检查 FASTQ 格式、read 数、长度分布；
   - 可选去除引物区和低质量末端；
   - 过滤过短、过长、含大量 N 的 reads。

2. **比对到目的序列**
   - 用 minimap2 `-ax map-ont` 或 mappy 把 reads 比对到参考；
   - 保留 primary alignment；
   - 过滤 identity 过低、覆盖度过低的 reads；
   - 反向互补的 reads 统一到参考方向。

3. **候选变异发现（第一遍）**
   - 逐位点 pileup；
   - 统计每个等位基因的 reads 数、频率、正负链支持数；
   - 支持 SNV、插入、缺失；
   - 做 indel 左对齐 / 归一化；
   - 根据 `min_reads`、`min_freq`、`strand_bias`、`homopolymer` 过滤；
   - 输出 `variants.tsv`。

4. **单条 read 校正（第二遍）**
   - 对每条 read，解析它的 CIGAR / MD / 变异列表；
   - 对每个差异位点：
     - 如果该差异对应的等位基因是“通过候选过滤的真实变异”，保留；
     - 否则视为测序错误，校正回参考；
   - 这样每条 read 被投影成“参考序列 + 它支持的真实变异组合”；
   - 多个真实变异会同时保留在同一条校正后的 read 上，因此天然保留了相位。

5. **单倍型计数**
   - 把校正后序列完全相同的 reads 归为一类；
   - 统计每类的 reads 数；
   - 计算比例和 Wilson 置信区间；
   - 与参考相同的那一类就是“完全一致的序列”。

6. **排序和输出**
   - 按 reads 数排序；
   - 输出 top-n；
   - 同时输出完整表、FASTA、QC 和报告。

优点：

- 能直接回答“是不是目的序列”；
- 对低深度、高错误率数据都比较稳；
- 保留多变异相位；
- 与公司“比对回共识 + 变异统计”的思路一致。

缺点：

- 对参考有依赖：如果真实变异不在候选列表里，会被校正掉；
- 需要通过 `min_freq` 控制“多低的变异算真”；
- 如果扩增子与目的序列差异很大（例如大片段替换），效果会下降。

### 6.3 方案 B：从头聚类 + 簇共识（备选）

这是更接近公司流程的方案，适合以下情况：

- 没有可靠参考；
- 预期有较大的结构变化；
- 想完全数据驱动，避免参考偏好。

步骤：

1. 先比对到参考做方向统一和长度筛选（可选）；
2. 用聚类工具按 identity 聚类：
   - `vsearch --cluster_fast` / `--cluster_size`；
   - 或 `MMseqs2`；
   - 或自研贪心聚类 + k-mer 预筛；
3. 每个簇用 `medaka` / `racon` / 简单多数投票生成共识序列；
4. 每个簇的 reads 数作为计数；
5. 把每个簇共识比对回参考，描述差异；
6. 输出 top-n。

优点：

- 不依赖参考；
- 可以发现有参考之外的新序列；
- 与公司交付流程接近。

缺点：

- 聚类阈值很关键，容易把错误拆成假簇，或把真变异合并；
- 低深度样本不稳定；
- 计算量比参考引导方案大。

### 6.4 方案 C：原始 reads 精确匹配（仅诊断）

直接统计原始 reads 中和参考完全一致的条数。

优点：

- 实现最简单；
- 可以作为 QC 指标，展示测序错误的影响。

缺点：

- 会严重低估“目标序列”的比例（test_data 中最低只有 2.4%）；
- 不能作为主要结果。

建议：保留为 `--mode exact`，只用于诊断和教学，不设为默认。

### 6.5 推荐策略

| 模式 | 用途 | 默认 |
|---|---|---|
| `reference` | 有目的序列，常规 PCR / 编辑验证 | 是 |
| `de-novo` | 无参考、复杂变异、怀疑参考不完整 | 否 |
| `exact` | 诊断测序错误、做对照 | 否 |

实现上三种模式共享：

- 输入输出模块；
- 比对模块；
- 变异描述模块；
- 注释模块；
- 报告模块。

区别只在“如何得到单倍型”这一步。

### 6.6 关键参数与默认值建议

第一版建议先用以下默认值，然后用 test_data 校准：

| 参数 | 建议默认 | 依据 |
|---|---:|---|
| `min_identity` | 0.90 | 尽量保留真实长 indel，同时过滤严重错误 |
| `min_coverage` | 10 | 低于此值标记低置信 |
| `min_reads` | 3 | 避免单条 reads 造成的假变异 |
| `min_freq` | 0.01 | 第一版先宽，配合过滤和置信区间 |
| `strand_bias` | 0.90 | 过滤单链假阳性 |
| `homopolymer` | 4 bp | 与公司过滤规则一致 |
| `top_n` | 20 | 满足大多数汇报需求 |

注意：`min_freq` 和 `min_reads` 对结果影响最大，最终值必须通过合成数据和公司结果双向校准。

### 6.7 错误校正的边界情况

需要专门处理：

1. **homopolymer / poly 结构**
   - 纳米孔在连续相同碱基处容易产生插入 / 缺失；
   - 参考公司过滤规则“poly 结构长度 ≥ 4 bp 且突变频率较低”；
   - 建议默认标记为可疑，而不是直接当真实变异。

2. **低复杂度区域**
   - 用局部熵或 k-mer 多样性识别；
   - 这些区域的 indel 需要更高阈值。

3. **读长大于扩增子**
   - 可能 read-through 或嵌合；
   - 比对时允许 soft-clip，必要时截取参考覆盖区。

4. **读长小于扩增子**
   - 截断 reads；
   - 只在 covered 区域判断，未覆盖区域不能算“和参考一样”。

5. **反向互补**
   - 统一到参考方向后再统计。

6. **混合单倍型**
   - 同一个 reads 上多个变异要保持在同一单倍型；
   - 不要拆成独立位点统计。

7. **PCR 重组**
   - 如果两个变异本来在不同分子上，却出现在同一条 read 上，会产生假单倍型；
   - 可通过频率组合检验和单倍型比例偏离 Hardy-Weinberg 预期来提示，但第一版只做警告。

### 6.8 比例的含义

程序输出的比例是 **reads-based proportion**，不是分子比例。原因：

- 没有 UMI，无法区分 PCR 重复；
- 纳米孔对不同长度 / 序列的 reads 可能有捕获偏好；
- 低深度时比例波动大。

建议输出：

- `count`：支持 reads 数；
- `proportion`：占比；
- `ci_low` / `ci_high`：95% 置信区间；
- `low_depth` 标记；
- 在报告里写明“比例为 reads 层面估计”。

### 6.9 引物处理

很多 FASTQ 里会包含引物区。引物错误会污染变异统计，所以需要：

1. 用户可选提供正向 / 反向引物；
2. 比对时允许 reads 两端 soft-clip；
3. 统计单倍型时只比较参考覆盖区；
4. 在报告里单独报告引物区变异。

---

## 7. GTF / 功能注释设计

### 7.1 注释目标

对每个单倍型，回答：

- 变异位于 CDS、UTR、内含子还是基因间区？
- 是 synonymous、missense、nonsense、stop-loss、start-loss 吗？
- 是 frameshift 还是 in-frame indel？
- 是否影响剪接位点？
- 多个变异组合起来，最终蛋白序列变成什么？

### 7.2 坐标映射问题

这是注释功能最容易出错的地方。

用户的“目的序列”通常是一段扩增子，不是整个基因组或转录本。要把变异注释到 GTF 上，必须知道：

- 扩增子对应哪个转录本；
- 扩增子在转录本上的起始位置；
- 扩增子方向（正链 / 负链）；
- CDS 的起始和阅读框。

解决办法有三层：

1. **最简单：CDS 配置模式**
   - 用户提供一个小 TSV / YAML：
     ```yaml
     name: ZNF8_amplicon
     cds_start: 55        # 扩增子参考上的 CDS 起始
     cds_end: 320
     strand: +
     frame: 0
     genetic_code: standard
     ```
   - 适合只有一个已知扩增子的常规实验；
   - 不依赖 GTF，最稳定，建议第一版先做这个。

2. **转录本模式**
   - 用户提供 transcript FASTA + GTF；
   - 程序把扩增子序列比对到转录本，自动推断坐标；
   - 用 GTF 中的 CDS 信息做注释；
   - 适合扩增子来自已知转录本的情况。

3. **基因组模式**
   - 用户提供 genome FASTA + GTF；
   - 程序先把扩增子比对到基因组，再把坐标映射到转录本 CDS；
   - 最复杂，第二版再做。

### 7.3 变异分类规则

| 变异类型 | 判断规则 | 注释结果 |
|---|---|---|
| 同义 SNV | 密码子改变但氨基酸不变 | `synonymous` |
| 错义 SNV | 氨基酸改变 | `missense` |
| 无义 SNV | 引入提前终止密码子 | `nonsense` / `stop_gained` |
| 终止密码子丢失 | 终止密码子变成氨基酸 | `stop_lost` |
| 起始密码子破坏 | 起始 ATG 被破坏 | `start_lost` |
| 移码 indel | indel 长度不是 3 的倍数 | `frameshift` |
| 整码插入 / 缺失 | indel 长度是 3 的倍数 | `inframe_insertion` / `inframe_deletion` |
| 剪接位点 | 位于内含子边界 ±1–2 bp | `splice_donor` / `splice_acceptor` |
| UTR | 位于 5' / 3' UTR | `5_prime_UTR` / `3_prime_UTR` |
| 内含子 / 基因间 | 不在 CDS / UTR | `intron` / `intergenic` |

对于整码 indel 和多个变异的组合，不能只看单个位点，必须：

1. 先把单倍型翻译成蛋白；
2. 与参考蛋白比对；
3. 报告最终蛋白差异。

### 7.4 多变异单倍型的注释

单倍型可能有多个变异。正确做法：

```text
参考 CDS → 翻译 → 参考蛋白
单倍型 CDS → 翻译 → 突变蛋白
两者比对 → 描述蛋白变化
```

而不是把每个变异的注释简单拼接。程序中应提供一个 `HaplotypeAnnotator` 模块统一处理。

---

## 8. 系统架构

### 8.1 分层架构

```text
┌─────────────────────────────────────────────────────────┐
│  界面层                                                  │
│  Windows GUI │ Web │ CLI │ R 包 │ Python API             │
├─────────────────────────────────────────────────────────┤
│  应用层                                                  │
│  参数校验 │ 任务编排 │ 批处理 │ 日志 │ 报告             │
├─────────────────────────────────────────────────────────┤
│  分析核心层                                              │
│  IO │ 比对 │ 变异检测 │ 校正 │ 单倍型 │ 注释 │ QC      │
├─────────────────────────────────────────────────────────┤
│  基础库层                                                │
│  minimap2/mappy │ pysam │ Biopython │ numpy │ pandas    │
└─────────────────────────────────────────────────────────┘
```

核心原则：**算法只实现一次，所有界面调用同一个核心。**

### 8.2 技术选型

| 模块 | 推荐技术 | 理由 |
|---|---|---|
| 核心语言 | Python 3.11 | 生信生态最全，打包路径清晰 |
| 比对 | minimap2（CLI 或 mappy） | 支持长 reads 和长 indel，公司流程同款 |
| BAM 处理 | pysam | 成熟稳定 |
| 序列处理 | Biopython | FASTA / FASTQ / 翻译 / 注释 |
| 编辑距离 | edlib 或 parasail | 快速计算 reads 与参考的差异 |
| 数据表 | pandas | 输出 TSV / Excel |
| 绘图 | matplotlib | QC 图 |
| CLI | Typer 或 Click | 易写、易测、自带 help |
| GUI | PySide6（Qt） | 成熟、跨平台、适合打包 exe |
| 打包 | PyInstaller（onedir） | Windows exe 最成熟 |
| Web MVP | Streamlit | 开发最快，适合内部工具 |
| Web 生产 | FastAPI + 前端 | 多用户、任务队列、API |
| R 包 | reticulate 或 processx 调 CLI | 避免重写算法 |
| 测试 | pytest + pytest-regressions | 回归测试 |
| 文档 | MkDocs Material | 可发布到网页 |

### 8.3 为什么核心选 Python

四个交付形态里，Python 的覆盖最广：

- Windows exe：PyInstaller 最成熟；
- Web：FastAPI / Streamlit 都是 Python；
- CLI：Python 直接写；
- R 包：R 通过 `reticulate` 或 `processx` 调用 Python 核心；
- Python 模块：天然就是 Python。

如果核心用 R：

- Windows exe 打包困难；
- Web 部署复杂；
- 仍需给 Python 用户一个接口。

所以推荐：**Python 核心 + 各语言薄封装**。R 包不重写算法，只做参数校验、调用和结果封装。

### 8.4 建议目录结构

```text
a_09_18_26_mapping_programs_dev/
├── 00_materials/
│   ├── programs_dev_info.md
│   ├── programs_dev_plan_1.md
│   └── ...
├── 01_data/
│   ├── test_data/                 # 已有测试数据
│   ├── refs/                      # 新增：整理后的目的序列、CDS 配置
│   └── expected/                  # 新增：公司结果整理成的回归基准
├── 02_code/
│   ├── src/nanopore_amplicon/
│   │   ├── __init__.py
│   │   ├── cli.py                 # 命令行入口
│   │   ├── config.py              # 参数与默认值
│   │   ├── io.py                  # FASTA / FASTQ / 样本表读写
│   │   ├── align.py               # 比对与过滤
│   │   ├── variants.py            # 候选变异发现
│   │   ├── correct.py             # read 校正
│   │   ├── haplotypes.py          # 单倍型构建与计数
│   │   ├── annotate.py            # CDS / GTF 注释
│   │   ├── report.py              # HTML / 表格 / 图
│   │   └── utils.py
│   ├── gui/                       # PySide6 界面
│   ├── web/                       # Streamlit / FastAPI
│   ├── rpkg/                      # R 包源码
│   ├── tests/                     # 单元测试与回归测试
│   ├── scripts/                   # 数据整理、基准生成脚本
│   └── pyproject.toml
├── 03_docs/                       # 用户手册、教程、FAQ
├── 04_results/                    # 运行输出（git 忽略）
└── tmp/                           # 临时文件（git 忽略）
```

---

## 9. 四个交付形态的具体设计

### 9.1 核心库（最重要）

包名：`nanopore_amplicon`

Python API 示例：

```python
from nanopore_amplicon import call_haplotypes

result = call_haplotypes(
    reads="sample.fastq.gz",
    reference="target.fasta",
    top_n=20,
    mode="reference",
    min_freq=0.01,
    gtf=None,
)

print(result.haplotypes.head())
result.to_dir("outdir/")
```

核心库必须：

- 不依赖任何界面；
- 可以在无网络环境运行；
- 所有参数都有默认值；
- 返回结构化对象，同时支持导出文件；
- 有完整的单元测试。

### 9.2 CLI 终端版本

命令设计：

```bash
# 单样本
nanoamp call \
  --reads sample.fastq.gz \
  --reference target.fasta \
  --top-n 20 \
  --outdir results/sampleA

# 带 GTF 注释
nanoamp call \
  --reads sample.fastq.gz \
  --reference target.fasta \
  --gtf genes.gtf \
  --transcript-id ENST00000xxxxx \
  --top-n 20 \
  --outdir results/sampleA

# 多样本批处理
nanoamp batch \
  --sample-sheet samples.tsv \
  --top-n 20 \
  --threads 8 \
  --outdir results/

# 检查环境
nanoamp doctor
```

`nanoamp doctor` 用于检查依赖（minimap2、pysam、参考文件）是否齐全，降低用户求助成本。

### 9.3 Windows GUI + exe

界面布局建议：

```text
┌────────────────────────────────────────────────────┐
│ 纳米孔 PCR 产物分析                                 │
├────────────────────────────────────────────────────┤
│ 1. 测序文件   [选择 FASTQ...]   sample.fastq.gz     │
│ 2. 目的序列   [选择 FASTA...]   target.fasta        │
│ 3. 输出目录   [选择目录...]     D:\results\sampleA  │
│                                                    │
│ 高级设置                                           │
│   模式： (•) 参考引导  ( ) 从头聚类  ( ) 精确匹配   │
│   显示前 n 条： [20]                               │
│   最低频率：   [1%]                                │
│   GTF 注释：   [可选]                              │
│   线程数：     [4]                                 │
│                                                    │
│              [开始分析]  [取消]                     │
├────────────────────────────────────────────────────┤
│ 进度：[██████████░░░░░░]  60%                      │
│ 状态：正在校正 reads...                             │
├────────────────────────────────────────────────────┤
│ 结果表：排名 | 序列 | 数量 | 比例 | 是否一致 | 变异  │
│ 1        | ...  | 1234 | 62.3%| 是       | -      │
│ 2        | ...  |  421 | 21.2%| 否       | del3bp │
├────────────────────────────────────────────────────┤
│ [导出 Excel] [导出 FASTA] [打开 HTML 报告] [批量]   │
└────────────────────────────────────────────────────┘
```

关键设计点：

- 默认值开箱即用，教授只需选两个文件；
- “高级设置”折叠，避免吓到非技术用户；
- 结果直接用中文列名显示；
- 支持拖拽文件；
- 批量模式：选择文件夹，自动识别 FASTQ，生成汇总表；
- 打包方式：PyInstaller `--onedir` + NSIS 安装包；
- 需要提前验证 pysam、numpy、PySide6、minimap2 在 PyInstaller 下的打包问题；
- minimap2 可以随程序打包一个 Windows 静态版本，避免用户单独安装；
- 首次运行做环境自检，出错时给出中文提示。

### 9.4 R 包 / Python 模块

Python 模块：

```python
import nanopore_amplicon as na

res = na.call_haplotypes("sample.fastq.gz", "target.fasta", top_n=20)
res.haplotypes          # pandas DataFrame
res.variants
res.qc
res.write("outdir/")
```

R 包（暂定名 `nanoporeAmplicon`）：

```r
library(nanoporeAmplicon)

res <- na_call(
  reads = "sample.fastq.gz",
  reference = "target.fasta",
  top_n = 20,
  mode = "reference"
)

res$haplotypes
na_write(res, "outdir/")
```

实现方式两种，推荐第一种：

1. **调用独立 CLI 可执行文件**（`processx` / `system2`）
   - R 包不依赖 Python 环境；
   - 用户安装 R 包时同时获得或指向一个 CLI 二进制；
   - 跨平台发布需要为 Windows / macOS / Linux 各准备一份。

2. **reticulate 调用 Python 包**
   - 实现简单；
   - 但要求用户配置 Python 环境，Windows 上容易出问题。

建议：

- 内部先用 reticulate 快速验证；
- 正式发布用 CLI 二进制方案，保证 R 用户无 Python 也能用。

### 9.5 Web 服务

分两步：

**第一步：Streamlit MVP（最快）**

```bash
streamlit run web/app.py --server.address 0.0.0.0 --server.port 8501
```

功能：

- 上传 FASTQ / 参考 FASTA；
- 选择参数；
- 提交任务；
- 显示进度；
- 在线表格 + 下载 ZIP。

优点：1–2 天能做出可用版本。

**第二步：FastAPI + 前端（正式版）**

- 后端：FastAPI；
- 任务队列：RQ / Celery / 简单线程池；
- 前端：Vue 或 React；
- 功能：
  - 用户登录；
  - 任务列表；
  - 结果持久化；
  - 批量上传；
  - 结果分享链接；
  - 资源限制和清理策略。

部署建议：

- 内网服务器：Docker 镜像 + docker-compose；
- 反向代理：Nginx；
- 数据目录：挂载大盘；
- 定期清理上传文件；
- 注意实验数据保密，默认不对外网开放。

---

## 10. 开发路线图

### Phase 0：需求冻结与测试数据整理（1–2 天）

任务：

- 与教授确认输入输出、参数、报告语言；
- 整理 test_data 的参考序列和预期结果；
- 建立 `01_data/refs/` 和 `01_data/expected/`；
- 确定项目名称、仓库地址、Python 版本；
- 搭建目录结构和 `pyproject.toml`。

产出：

- 本方案确认版；
- 参考序列文件；
- 回归测试基准表；
- 代码仓库骨架。

### Phase 1：核心算法 + CLI MVP（约 1 周）

任务：

- 实现 FASTQ / FASTA 读写；
- 实现 minimap2 比对和过滤；
- 实现候选变异发现；
- 实现 read 校正和单倍型计数；
- 实现 `haplotypes.tsv`、`variants.tsv`、QC 输出；
- 实现 `nanoamp call` 命令；
- 用 TSM / ZNF8 / nano_seq / SD 数据做初步验证。

产出：

- 可在终端运行的 MVP；
- 单样本结果与公司结果对比报告；
- 第一版参数默认值。

### Phase 2：GTF / CDS 注释（约 3–5 天）

任务：

- 实现 CDS 配置模式；
- 实现密码子翻译和蛋白比对；
- 实现同义 / missense / nonsense / frameshift 分类；
- 实现转录本模式的自动坐标映射；
- 增加注释单元测试。

产出：

- `annotate.py` 模块；
- 注释示例和文档；
- 带功能注释的结果表。

### Phase 3：打包与 Python / R 接口（约 3–5 天）

任务：

- `pip install -e .` 可用；
- 构建独立 CLI（Windows / Linux）；
- 创建 R 包骨架；
- 实现 R 调用 CLI 的封装；
- 编写安装说明。

产出：

- Python wheel / conda 环境文件；
- R 包源码；
- 跨平台 CLI 二进制。

### Phase 4：Windows GUI + exe（约 1 周）

任务：

- 实现 PySide6 界面；
- 接入核心库；
- 实现进度条、日志、结果表、导出；
- 用 PyInstaller 打包；
- 在干净的 Windows 环境测试；
- 准备中文使用手册。

产出：

- `纳米孔PCR分析器.exe`；
- 安装包；
- 图文教程。

### Phase 5：Web 服务（约 1 周）

任务：

- Streamlit MVP；
- 上传、任务、结果展示；
- 必要时升级到 FastAPI；
- Docker 部署；
- 内网测试。

产出：

- Web 服务；
- 部署文档；
- 使用说明。

### Phase 6：硬化、批量与文档（持续）

任务：

- 多样本批处理；
- 96 孔板 / barcode 拆分；
- 性能优化；
- 更多边界测试；
- CI（GitHub Actions / GitLab CI）；
- 用户手册、FAQ、视频教程；
- 版本发布。

---

## 11. 基于 test_data 的验证方案

### 11.1 整理测试数据

建议新增：

```text
01_data/
├── test_data/          # 原始测试数据，不动
├── refs/
│   ├── ZNF8_WT.fasta               # 来自 ZNF8/2026.8.29-wt 的 WT 共识序列
│   ├── TSM_293T_E4.fasta           # E4 的 293T 对照参考
│   ├── TSM_293T_G2.fasta           # G2 的 293T 对照参考
│   ├── nano_293T_G1..G5.fasta      # 各对照参考
│   └── cds_configs/                # 各靶点的 CDS 配置
└── expected/
    ├── TSM_expected.tsv
    ├── ZNF8_expected.tsv
    ├── nano_expected.tsv
    └── SD_expected.tsv
```

其中 `expected` 表由公司 `.变异统计表.xlsx` 和 `*.var.xls` 整理得到，作为回归基准。

### 11.2 回归测试 1：复刻公司结果

对 TSM / nano_seq / ZNF8：

```text
输入：样本 FASTQ + 公司 *.1.seq 作为参考
期望：输出的少数变异与公司 *.变异统计表.xlsx 基本一致
```

因为公司 `*.1.seq` 是主导共识序列，程序应该：

- 把大多数 reads 归到参考单倍型；
- 把公司 xlsx 里报告的少数变异复现出来；
- 比例差异在可接受范围内。

这是最直接的“和现有软件对齐”测试。

### 11.3 回归测试 2：相对 WT 的编辑结果

对 ZNF8：

```text
输入：克隆 FASTQ + WT 参考（2026.8.29-wt 或 ZNF8.dna）
期望：top 单倍型等于该克隆公司的 *.1.seq
     差异位点等于编辑位点
```

这个测试回答教授最关心的问题：

> 这个克隆里，有多少序列是我想要的编辑序列？

### 11.4 回归测试 3：SD 数据交叉验证

SD 目录没有 FASTQ，但可以用：

```bash
samtools fastq -T '*' sample.sorted.bam > sample.fastq
```

把 BAM 还原成 FASTQ，然后用 `for.ref.fa` 作为参考跑程序。

期望：

- 复现 `*.var.xls` 中 PASS 的变异；
- 复现 FILTERED 变异并给出类似过滤原因；
- 对高深度样本（如 `G22608076105`，13,897 reads）验证性能。

这是和另一套公司流程的交叉验证。

### 11.5 合成数据基准

回归测试只能说明“和公司结果像”，不能给出绝对准确度。因此需要合成数据：

1. 设计 3–5 个已知单倍型；
2. 按已知比例混合，例如 70% / 20% / 8% / 2%；
3. 用纳米孔错误模型生成 reads：
   - 推荐 `badread`；
   - 或自定义错误模型；
4. 设置不同覆盖度：50×、200×、1000×；
5. 设置不同错误率：1%、3%、5%；
6. 评估：
   - 单倍型是否全部恢复；
   - 比例误差；
   - 假阳性变异数；
   - 召回率、精确率；
7. 用结果校准 `min_freq`、`min_reads`、`min_identity`。

合成数据是本项目最关键的验证手段，因为真实数据没有 known truth。

### 11.6 边界测试

必须覆盖：

- 只有 1 条 read；
- 0 条 read / 空文件；
- 所有 reads 完全相同；
- reads 全部反向互补；
- 扩增子含引物；
- 大插入（≥ 10 bp）；
- 大缺失（≥ 10 bp）；
- homopolymer 区域；
- 含 N 碱基；
- read 长度远超 / 远短于扩增子；
- 多个单倍型且比例接近（如 50%/50%）；
- 中文路径、中文文件名、空格路径；
- Windows 和 Linux 路径差异。

### 11.7 性能测试

- 10^4、10^5、10^6 reads 的耗时和内存；
- 200 bp、1 kb、5 kb 扩增子；
- 96 个样本批处理；
- 并发 4 / 8 / 16 线程；
- 低配笔记本和服务器分别测试。

---

## 12. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 纳米孔 reads 并非逐条准确 | 原始精确计数严重失真 | 默认做校正 / 聚类，同时报告 raw exact match 作为对照 |
| 参考偏好（reference bias） | 真实新变异被校正掉 | 提供 `de-novo` 模式；`min_freq` 可调；合成数据校准 |
| 聚类阈值难定 | 过度拆分或过度合并 | 用 test_data + 合成数据双校准；参数写进输出 |
| 比例不是分子比例 | 结论被过度解读 | 报告 reads-based proportion + 置信区间 + 文字说明；建议加 UMI |
| GTF 坐标映射复杂 | 注释错误 | 第一版先做 CDS 配置模式；GTF 模式逐步推进 |
| Windows 打包失败 | 无法交付 exe | Phase 1 就开始验证 PyInstaller + pysam + minimap2 |
| R 用户没有 Python | R 包不可用 | 正式版 R 包调用独立 CLI 二进制 |
| Web 数据安全 | 实验数据泄露 | 默认内网部署；登录；定期清理；不开放公网 |
| 中文路径 / 编码 | 文件读写失败 | 全程 UTF-8；Windows 专项测试 |
| 低深度样本 | 频率不可靠 | 输出置信区间和低深度标记，不隐藏不确定性 |
| 公司格式变化 | 兼容性失效 | 输出自己的标准格式；公司格式作为可选导出 |

---

## 13. 需要确认的问题

在正式开发前，建议和教授确认以下问题：

### 实验与数据

1. 目的序列通常多长？200 bp、500 bp、1 kb，还是更长？
2. 扩增子是否包含引物区？需要自动去引物吗？
3. 纳米孔数据是什么化学版本和 basecalling 模型（R9 / R10，fast / hac / sup）？
4. 每个样本大概多少 reads？几十、几百，还是上万？
5. 是否存在 293T / WT 对照？对照是否每次都测？
6. 是否有 UMI 或重复实验？如果没有，比例只能作为 reads 层面的估计。
7. 需要区分 PCR 错误、测序错误和真实突变吗？

### 输入输出

8. 输入是一个 FASTQ 还是多个 FASTQ？
9. 是否需要从 barcode 自动拆分混样数据？
10. 输出报告要中文还是英文？
11. 需要 Excel、HTML、PDF 还是只要 TSV？
12. 是否需要与公司现有的 `*.var.xls` / `*.变异统计表.xlsx` 格式兼容？

### 注释

13. GTF 对应的是基因组还是转录本？
14. 扩增子在转录本上的坐标是否已知？
15. 需要注释哪些类型？同义、missense、nonsense、frameshift、剪接位点？
16. 是否需要蛋白序列和密码子级别的展示？

### 部署与使用

17. Windows 版本是什么？是否有管理员权限？
18. Web 服务部署在哪个服务器？内网还是公网？
19. 预计同时多少人在线使用？一次提交多少样本？
20. 是否有数据保密要求？
21. 是否需要图形化安装包，还是绿色版即可？
22. 是否需要预留命令行批处理接口给现有 LIMS / 流程？

### 项目协作

23. 代码托管在哪里？GitHub、GitLab 还是本地？
24. 是否允许多人在同一个仓库协作？
25. 是否需要英文文档 / 论文致谢 / 开源许可证？

---

## 14. Git 与协作规范

### 14.1 已执行的版本管理

- 在项目根目录初始化 Git 仓库；
- 提交 `00_materials/`、`01_data/test_data/` 和本方案；
- 忽略 `tmp/`、Python 缓存、构建产物和分析输出；
- 为后续代码开发建立干净基线。

### 14.2 建议的分支策略

```text
main            # 稳定版本，随时可发布
dev             # 日常开发
feature/xxx     # 单个功能
fix/xxx         # 修 bug
release/x.y.z   # 发布准备
```

小团队也可以简化为：

```text
main            # 稳定
dev             # 开发
feature/xxx     # 功能分支
```

### 14.3 提交信息规范

推荐使用 Conventional Commits：

```text
feat: 增加参考引导单倍型计数
fix: 修复反向互补 reads 的比例统计
docs: 补充 Windows 安装说明
test: 增加 ZNF8 WT 回归测试
refactor: 拆分 annotate 模块
chore: 更新依赖版本
```

### 14.4 数据管理策略

当前 `test_data` 约 81 MB，可以直接放在 Git 里，作为固定测试集。

后续如果出现以下情况，建议迁移到 Git LFS 或 DVC：

- 单文件超过 50–100 MB；
- 数据总量超过几百 MB；
- 频繁增加新的 FASTQ / BAM；
- 多人协作时仓库克隆太慢。

建议原则：

- 代码、配置、文档、小测试数据进 Git；
- 大 FASTQ / BAM 原始数据用 LFS / DVC / NAS 管理；
- `04_results/` 和 `tmp/` 永远不进 Git；
- 每次发布用 Git tag 标记，例如 `v0.1.0`。

### 14.5 发布流程建议

```text
1. 在 dev 上开发并测试
2. 合并到 release/x.y.z
3. 跑完整回归 + 合成数据基准
4. 打 tag vX.Y.Z
5. 生成 Windows exe、Python wheel、R 包
6. 写 release notes
```

---

## 15. 优先级总表

| 优先级 | 功能 | 阶段 |
|---|---|---|
| P0 | FASTQ + 参考 → 单倍型表 | Phase 1 |
| P0 | top-n 序列、数量、比例 | Phase 1 |
| P0 | 候选变异表和 QC | Phase 1 |
| P0 | 与公司结果回归验证 | Phase 1 |
| P0 | 命令行版本 | Phase 1 |
| P1 | CDS 功能注释 | Phase 2 |
| P1 | 合成数据基准 | Phase 2 |
| P1 | Python 包 | Phase 3 |
| P1 | R 包 | Phase 3 |
| P1 | Windows GUI | Phase 4 |
| P1 | exe / 安装包 | Phase 4 |
| P2 | GTF 转录本模式 | Phase 2–3 |
| P2 | Web 服务 | Phase 5 |
| P2 | 批量样本 | Phase 5–6 |
| P3 | barcode 自动拆分 | Phase 6 |
| P3 | 公司格式导出 | Phase 6 |
| P3 | PDF 报告 | Phase 6 |

---

## 16. 结论

这个项目的技术难点不在“写一个 GUI”，而在**如何在有测序错误的前提下，准确地把 PCR 产物分成若干真实序列类型并定量**。

test_data 已经证明：

- 原始 reads 的完全匹配比例最低只有 2%–4%，直接计数会严重误导；
- 公司现有流程本质上就是“聚类 + 共识 + 变异统计”；
- 我们的程序可以把这条路线做得更通用、更易用，并增加单倍型表、功能注释和多形态交付。

建议的开发顺序是：

```text
先做核心算法和 CLI
  → 用 test_data 回归验证
  → 增加 CDS / GTF 注释
  → 打包 Python / R 接口
  → 做 Windows GUI
  → 最后做 Web 服务
```

只要核心算法先用 test_data 和合成数据验证扎实，后面的 GUI、exe、R 包和 Web 都只是不同外壳，开发和维护成本会低很多。
