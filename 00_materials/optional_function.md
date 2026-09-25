# nanoamp 可选功能开发方案：功能注释（§1.1 第 6 项）

> 依据：`00_materials/programs_dev_plan_1.md` **§1.1 委托原话拆解 第 6 项**（本轮范围的唯一来源），
> 并参考同文件 §1.2.3（"把序列差异翻译成生物学结论"）、§7（GTF / 功能注释设计）、§15（优先级总表）
> 现状基线：`c3a3329`，包版本 0.1.0，`Imports` 10 个包，功能测试 168/168，`R CMD check` Status: OK
> 2026-09-23 更新（**第五轮，定稿**）：参考信息**改为只走联网按需拉取**——
> 用户**既不提供 GTF/FASTA，也不需要任何手工准备**；程序只维护一个**只读缓存**（§2A.4）。
> 联网可行性已逐条实测（§2A.2），并发现两个"原以为要不到"的东西其实都能在线拿到：
> **`MANE_Select` 标记**（在 `tag` 字段里）与**官方蛋白序列**（可直接用于 V1 对拍）。
> 已确认的三项决定：① `All` 采用"每单倍型 × 每转录本一行 + 两个汇总列"（§2D.3）；
> ② **保留路线一**（CDS 配置）作为退路（§2.1）；③ **取消本地 GTF/FASTA 输入**（§2A/§2B）。
> 本文件状态：**第 1 版方案（定稿范围），供确认。只写方案，不写实现代码。**

---

## 0. 需求范围（本方案只做这两条）

`programs_dev_plan_1.md` §1.1 第 6 项原文：

> 6. 可选功能：
>    - 连接 GTF 等注释信息；
>    - 判断变异属于移码、提前终止、missense 等。

拆成两个可验收的交付物：

| 编号 | 交付物 | 对应原文 | 本方案阶段 |
|---|---|---|---|
| **D1** | **变异功能分类**：把每个变异/单倍型判为移码、提前终止、missense、同义、终止丢失、起始丢失、整码插入/缺失、UTR、内含子/基因间等 | "判断变异属于移码、提前终止、missense 等" | A2–A4 |
| **D2** | **GTF 注释接入**：读取 GTF，把坐标与 CDS/UTR/外显子/内含子结构接起来，供 D1 使用 | "连接 GTF 等注释信息" | A1、A5 |

**两条是同一件事的两半**：D1 是"判什么"，D2 是"拿什么坐标去判"。所以本方案把它们做成
一条管线、两个坐标来源，而不是两个独立功能。

**明确不在本轮范围**（§15 优先级表中的 P3 项，与本项需求无关）：
公司格式导出、PDF 报告、barcode 自动拆分、Web 服务、Windows GUI。这些如需推进应各自单独立项。

---

## 1. 现状核实（写方案前实测，结论直接影响设计）

| # | 事实 | 依据 | 对设计的影响 |
|---|---|---|---|
| F1 | **仓库与测试数据里没有任何 GTF/GFF/BED 文件** | `find 01_data 03_dependence -iname "*.gtf*" -o -iname "*.gff*" -o -iname "*.bed"` 无结果 | 本地没有注释文件，**也不能自造一个来"装作跑通"** → 改为**联网按需拉取**（§2A），并已实测可行（F14） |
| F2 | **42 条参考序列里只有 9 条长度能被 3 整除**（208–1068 bp，中位数 320） | 实测 `reference.self` / `consensus` | **参考序列本身就是含引物/UTR 的扩增子，不是纯 CDS**。因此"把整段参考当 CDS 翻译"是错的，必须由用户指明 CDS 区间 |
| F3 | 参考 FASTA 头部只有文件名，无任何结构注释 | `head -1 .../E4-3....1.seq` → `>E4-3_TSM20260826-..._H08.1` | 无法从数据推断 CDS 边界、阅读框或链向 |
| F4 | 公司的变异统计表**没有任何功能注释列**（9 列：位置/类型/碱基/比值/比例/位点结果/峰图） | 实测 `E4-19..._B09.2.变异统计表.xlsx` | **没有可比对的外部验收基线**，验收必须靠构造已知答案的合成数据 |
| F5 | 单倍型表已带完整序列 | `haplotypes.tsv` 含 `sequence` 列（`R/correct.R::build_haplotype_table`） | 蛋白级注释可直接"取 CDS → 翻译"，无需重新组装 |
| F6 | `Biostrings::translate()` 与 `GENETIC_CODE` 可用 | `translate(DNAString("ATGAAATTTTAA"))` → `MKF*`；`getGeneticCode("2")` 返回同名向量；`GENETIC_CODE_TABLE` 是 20 行 data.frame | **零新增依赖** |
| F7 | `translate()` 的三个行为边界 | 尾部不足一密码子**静默丢弃**（`ATGAAATTT`→`MKF`）；含 `N` **直接报错**；`genetic.code` 必须是**与 `GENETIC_CODE` 同名**的向量，传字符串名称报 `must have the same names as predefined constant` | 注释层必须自己处理部分密码子与歧义碱基 |
| F8 | `R/zzz.R` 已有可用的成对比对封装 `pa_pairwise_alignment()`（pwalign/Biostrings 双向兼容） | 现有代码 | 蛋白比对可直接复用，不需要新依赖 |
| F9 | **公司 BAM 不含任何基因组坐标** | `scanBamHeader` 显示唯一 target 是 `for.ref`（长度 493），`CL` 行显示公司用 `minimap2 ... <sample>.for.ref.fa` 把 reads 比对到**扩增子参考**；`rname` 只有 `for.ref` 与 `NA` | 交付数据里**没有** GRCh38 坐标；GTF 路线的坐标必须由用户另外提供 |
| F10 | `01_data/test_data/ZNF8/ZNF8.dna` 是 SnapGene 文件（554 KB） | 内含序列，但特征名不易可靠解析；仓库中仅此一个 | 不能当作可靠的 CDS 来源依赖；只能提示用户"这可能是你取 CDS 的地方" |
| **F11** | **扩增子坐标可以自动恢复到 GRCh38**（实测成功） | 取 Ensembl GRCh38 `chr19:58,276,949-58,304,791`，用 `grep` 精确匹配：ZNF8 的 WT 320 bp 共识序列 **100% 精确命中** `chr19:58,285,652-58,285,971`（0 错配）；按坐标反切序列与 WT `identical()` 为 TRUE。另外 22 条克隆用局部比对全部落在**同一坐标**（pid 91.6–100%） | **不再需要委托方提供扩增子坐标**：可由程序自行定位（§2C）。原"阻塞项"已消除（§11.C） |
| **F12** | **扩增子是"基因组型"扩增子，跨越外显子/内含子边界** | 上例中该 320 bp 区间 = 外显子2 上游内含子 65 bp + **外显子2 全部 127 bp** + 下游内含子 128 bp；在 ZNF8-201（canonical，575 aa）与 ZNF8-203（105 aa）两个转录本下都是 **127 bp 编码 + 193 bp 非编码** | **必须在基因组坐标系下工作**，不能把扩增子当成转录本切片。后果分类要按"基因组区间类型"（CDS / UTR / intron / 剪接区）判定；蛋白注释要走"外显子拼接后再应用变异"的路径（§2B.3） |
| **F13** | **同一扩增子在不同转录本上后果不同**（实测） | 上述区间在 ZNF8-201 与 ZNF8-203 下编码/非编码比例相同，但两转录本 CDS 长度相差 470 aa；Ensembl 该基因共 5 个蛋白编码转录本 | 转录本选择**必须显式确定**（R12）。由于扩增子坐标现在可自动恢复，我们可以在程序里**列出候选转录本及其后果**供人工确认，而不是要求委托方事先指定 |

| **F14** | **公开 API 能按需提供全部所需参考信息**（实测，见 §2A.2） | Ensembl REST 的 `sequence/region`、`sequence/id?type=cds|protein`、`overlap/region?feature=transcript`、`overlap/id?feature=cds` 全部 HTTP 200 且内容正确；UCSC API 可作备选 | **不再需要用户准备 GTF/FASTA**：改成按需拉取，每个扩增子只需几 KB |
| **F15** | **`MANE_Select` 与官方蛋白都能在线拿到**（实测） | `overlap/region` 返回的 `tag` 含 `MANE_Select`（ENST00000621650）；把 API 给的 CDS 自行翻译与 API 给的蛋白 **`identical() == TRUE`**（575 aa） | 上一版"MANE 要不到、只能靠 `All` 补偿"（2B.2）**作废**；V1 正确性闸门可完全在线执行 |
| **F16** | **Ensembl 取序会静默截断**（实测） | 请求 100/200 kb 完整返回；请求 500 kb 与 1 Mb 均只回 **331,965 bp**；请求 5 Mb 回 617,617 bp 且被钳到 19 号染色体末端——**全部 HTTP 200，不报错** | 必须分块（上限 100 kb）+ 校验实得长度（§2A.3、R16）。对本工具影响小（扩增子仅几百 bp），但绝不能默认相信返回值 |

**F1 + F2 + F4 原本是本方案的三条硬约束**（GTF 要用户给、CDS 坐标不能猜、验收只能靠合成数据）。
**F14 与 F15 已把前两条中的"要用户给"部分解除**：参考改为按需拉取、MANE 与官方蛋白在线可得。
F4（无功能注释基线）仍然成立，验收依旧以合成数据 + §7.5 三重自检为主。
**F9 是 GTF 路线的新增硬约束**：GENCODE 坐标是基因组坐标，而交付物是扩增子坐标，
两者之间**缺一个定位环节**（见 §2.5 与 §2B）——但 **F11 证明这个环节可以自动化**。

---

## 2. 两条坐标来源（D2 的核心取舍）

因为 F1（无 GTF）与 F2（参考不是纯 CDS），必须先解决"CDS 在哪里"。§7.2 原本给了三层方案，
本方案按其"最稳定者优先"的建议排序，但**同时承认委托方明确点名了 GTF**，所以两条都要做：

### 2.1 路线一：CDS 配置（默认，P0）
用户只需给出扩增子参考上的 CDS 区间，不依赖任何外部注释文件。

```json
{
  "name": "ZNF8_amplicon",
  "assembly": "amplicon",
  "cds": { "start": 55, "end": 320, "strand": "+", "frame": 0, "boundaries": "inclusive" },
  "genetic_code": "Standard",
  "primers": { "forward": null, "reverse": null },
  "reference_md5": null,
  "notes": "company cluster-1 consensus as reference"
}
```

| 字段 | 必需 | 语义 |
|---|---|---|
| `name` | 是 | 注释对象名，写入输出与 manifest |
| `assembly` | 是 | `"amplicon"`：坐标相对**输入参考序列**（1-based） |
| `cds.start` / `cds.end` | 是 | CDS 的 1-based 闭区间；`end` 可省略表示到参考末端 |
| `cds.strand` | 是 | `"+"` / `"-"`；`"-"` 时对区间反向互补后再翻译 |
| `cds.frame` | 是 | `0`/`1`/`2`：从 CDS 起点跳过几个碱基 |
| `cds.boundaries` | 否 | `"inclusive"`（默认）或 `"half_open"` |
| `genetic_code` | 否 | 默认 `Standard`；取 `GENETIC_CODE_TABLE` 的 `name` 或 `id`，大小写不敏感，内部映射到 `getGeneticCode()`（F7） |
| `primers.forward/reverse` | 否 | 给出则**用引物序列定位 CDS 边界**，优先于显式坐标（见 §2.3） |
| `reference_md5` | 否 | 给出则强校验参考文件（复用 `R/io.R::safe_md5()`），防止配置配错参考（如误用 wt） |

**示例配置必须随仓库交付**：`configs/example_cds.json` + `configs/README.md` 说明如何取得
CDS 边界（从公司共识序列的注释、SnapGene 或已知引物位置读出），以及如何自检
（首密码子应为 `ATG`、末密码子应为终止密码子）。

### 2.2 路线二：GTF 接入（P0/P1，委托方点名项）

**已确认委托方可以提供 `gencode.v50.primary_assembly.annotation.gtf`。** 这是一份
**全基因组**注释（GENCODE 覆盖 ~6 万基因 / ~20 万转录本），不是针对某个扩增子的。
由此产生三个必须处理的问题：

1. **坐标系统不同**：GENCODE 用 GRCh38 基因组坐标（1-based，含内含子）；而 nanoamp
   现在只有扩增子坐标（`variants.tsv` 的 `Pos` 是**相对扩增子参考**的 1-based 位置，
   见 `R/variants.R`），且交付数据里**没有任何基因组坐标**（F9）。两者之间必须有一个
   定位环节。
2. **必须指定看向哪个转录本**：同一个变异在不同转录本上后果可能不同（是否在 CDS 内、
   阅读框、有无该外显子）。全基因组 GTF 上"全部注释"没有意义。
3. **需要与 GTF 版本匹配的参考基因组**：GTF 只有坐标，拿不到序列就切不出 CDS。

因此路线二按 **§7.2 的第 3 层（基因组模式）** 实现，并在其前面加一个定位环节：

```json
{
  "name": "ZNF8_clone3",
  "assembly": "genome",
  "genome_fasta": "refs/GRCh38.primary_assembly.genome.fa",
  "gtf": "refs/gencode.v50.primary_assembly.annotation.gtf",
  "amplicon": {
    "chrom": "chr19",
    "start": 58120000,
    "end": 58120600,
    "strand": "+"
  },
  "transcript_id": "ENST00000000000",
  "genetic_code": "Standard"
}
```

`amplicon` 也可以用引物代替坐标（由程序在参考基因组上定位）：

```json
  "amplicon": {
    "forward_primer": "ACGT...",
    "reverse_primer": "TGCA..."
  },
```

工作方式：

1. **定位**：把用户给的扩增子参考（公司共识序列）比对到参考基因组，或按
   `chrom/start/end/strand` 直接取区间，确定扩增子在基因组上的**确切边界**；
2. **选转录本**：按 `transcript_id` 从 GTF 取出该转录本的 `CDS`（含 `phase`）/`exon`
   /`UTR` 行；若未指定则报错，**不自动猜**（见 §2B）；
3. **映射坐标**：把扩增子坐标 → 基因组坐标 → 转录本坐标 → CDS 坐标，得到
   `{seq, start, end, strand, frame}`；
4. 交给与路线一**完全相同**的分类/翻译/蛋白比对管线。

坐标映射规则（必须写成可单测的纯函数）：

- 位于扩增子参考反向互补链上的变异，需在比对到基因组时同步翻转（`A>G` 变 `T>C`）；
- 落在内含子内的变异 → `intron`；落在 UTR → `5_prime_UTR` / `3_prime_UTR`
  （这两类只有 GTF 路线能判，是 GTF 相对路线一的**唯一增量信息**）；
- 跨越外显子/内含子边界的变异 → 明确标记 `exon_intron_boundary`，不猜测。

不引入 `rtracklayer` / `GenomicFeatures`（重依赖且本需求用不到）。

### 2.3 为什么保留"引物锚定"

indel 会改变坐标：若某单倍型在 CDS 上游有 indel，"按参考坐标切片"与"按单倍型切片"会得到
不同的阅读框。定位顺序（按稳健性）：

1. **引物锚定**：配置给了引物时，在参考与单倍型上分别定位引物，CDS 边界按"引物 3' 端之后
   的固定偏移"计算。引物之间的 indel 不再破坏阅读框；
2. **参考坐标**（默认）：直接按坐标切片——因为单倍型序列已是"应用变异后的完整序列"，
   只要 indel 不跨越边界就正确；
3. **边界异常**：若单倍型 CDS 切片长度不满足 `(len - frame) %% 3 == 0`，**不强行翻译**，
   标记 `cds_boundary_disrupted` 并跳过蛋白注释，避免输出错误蛋白。

### 2.4 两条路线的关系

```text
   ┌────────────────────────┐        ┌──────────────────────────────────────┐
   │ 路线一 CDS 配置         │        │ 路线二 GTF 基因组模式                 │
   │ 用户直接给扩增子 CDS 坐标│        │ 参考基因组 FASTA + GENCODE GTF        │
   │                        │        │ + 扩增子基因组坐标/引物 + transcript_id│
   └───────────┬────────────┘        └──────────────────┬───────────────────┘
               │                                        │ ① 定位扩增子（基因组坐标）
               │                                        │ ② 选转录本，取 CDS/exon/UTR
               │                                        │ ③ 扩增子坐标→基因组→转录本→CDS
               └───────────────────┬────────────────────┘
                                   ▼
                    统一的 CDS 描述 {seq, start, end, strand, frame}
                    附：区间类型图（CDS / UTR / intron）
                                   ▼
                    统一的分类 / 翻译 / 蛋白比对 / 输出管线
```

**关键点**：D1（判什么）只实现一次，两条路线只在"坐标从哪来"上不同。这样 GTF 接入不会
引入第二套分类逻辑；路线二多出来的只是**区间类型**（UTR / 内含子 / 剪接边界）。

---

### 2.5 两条路线的选择建议

| | 路线一 CDS 配置 | 路线二 GTF 基因组模式 |
|---|---|---|
| 需要的额外文件 | 无（只要扩增子参考） | **参考基因组 FASTA** + 扩增子基因组坐标/引物 + transcript_id |
| 配置难度 | 低（一次量出 CDS 起止） | 中（要拿到坐标与转录本号） |
| 能判断 | CDS 内后果 | CDS 内后果 **+ UTR / 内含子 / 剪接边界** |
| 出错面 | 小 | 大（三重坐标映射） |
| 适用 | 已明确知道扩增子覆盖哪个 CDS | 扩增子边界不清、或需要 UTR/剪接信息 |

**建议：两条都实现，共用 D1 管线。** 日常用路线一（稳）；需要 UTR/内含子结论时用路线二。

---

## 2A. 参考来源：只走联网按需拉取

**需求方决定：手工准备 GTF（约 1.5 GB）与 GRCh38 FASTA（约 3 GB）太麻烦，
且不再提供本地文件输入——参考信息一律联网按需拉取。**

因此本方案**没有** `--gtf` / `--genome` / `--ref-source` / `--offline` 这些参数；
用户唯一的参考相关操作是（可选的）清缓存。程序内部维护**只读缓存**以避免重复请求。

### 2A.1 核心洞察：不需要整份基因组，也不需要整份 GTF

前面几版方案默认"下载 4.5 GB 再本地查询"，但**本工具只需要极小的切片**：

| 需要什么 | 实际用量 |
|---|---|
| 扩增子所在区间的基因组序列 | 每个扩增子 **200 bp – 1.1 kb**（实测 `01_data` 的 42 条参考：208–1068 bp） |
| 该区间的转录本/CDS/外显子结构 | 一个区间通常重叠 **1–10 个转录本**（ZNF8 实测 8 个） |
| 该转录本的 CDS 与蛋白 | **1.7 kb** 与 **575 aa**（实测 ENST00000621650） |

**结论：按需拉取的量级是"每个扩增子几 KB"，而不是 4.5 GB。** 实测一条命令即可取到全部所需信息。

### 2A.2 已实测可用的公开 API（全部 HTTP 200，内容已验证）

| 用途 | 端点 | 实测结果 |
|---|---|---|
| 区间序列 | `rest.ensembl.org/sequence/region/human/<chr>:<s>..<e>:<strand>` | 返回 `text/x-fasta`，头部含组装与坐标，如 `>chromosome:GRCh38:19:58285652:58285971:1` |
| 转录本 CDS | `.../sequence/id/<ENST>?type=cds` | ENST00000621650 → 1728 bp，首密码子 `ATG`、末密码子 `TAG` |
| 转录本蛋白 | `.../sequence/id/<ENST>?type=protein` | 575 aa |
| 区间内重叠转录本 | `.../overlap/region/human/<chr>:<s>-<e>?feature=transcript` | 返回 8 条，**含 `assembly_name=GRCh38`、`is_canonical`、`biotype`、`tag`** |
| 某转录本的 CDS 坐标块（含 `phase`） | `.../overlap/id/<ENST>?feature=cds` | 24 个块，含 `start/end/strand/phase` —— **等价于 GTF 的 CDS 行** |
| 备选序列源 | `api.genome.ucsc.edu/getData/sequence?genome=hg38;chrom=..;start=..;end=..` | HTTP 200（JSON），可作为 Ensembl 的备选（**注意 UCSC 用 `chr19`、0-based**） |

**两个意外收获**：

1. **`tag` 字段里带 `MANE_Select`**！上一版方案里"MANE 要不到"（2B.2 第 5 项）的缺口
   就此消除——不需要额外文件，API 直接给：
   ```
   ENST00000621650 tags=['gencode_basic','Ensembl_canonical','gencode_primary','MANE_Select']
   ```
   于是 §2D 的默认选项可以真正落在 MANE Select 上，而不是"没有权威只能全选"。
2. **V1 自检（§7.5）可以在线完成**：实测把 API 给的 CDS 自行翻译，与 API 给的官方蛋白
   **完全一致**（575 aa，`identical() == TRUE`）。也就是说"参考蛋白对拍"这条最强闸门
   不需要下载任何官方文件就能执行。

### 2A.3 一个必须处理的坑：区间取序会**静默截断**

实测 Ensembl 的 `sequence/region` 在请求较大区间时**不报错但少给碱基**：

| 请求跨度 | HTTP | 实得长度 | 结果 |
|---|---|---|---|
| 100 kb | 200 | 100,001 bp | 完整 |
| 200 kb | 200 | 200,001 bp | 完整 |
| 500 kb | 200 | **331,965 bp** | **静默截断** |
| 1 Mb | 200 | **331,965 bp** | **静默截断** |
| 5 Mb | 200 | **617,617 bp** | 且被钳到染色体末端（19 号染色体长 58,617,616） |

对策（写进实现要求）：

1. **分块**：单次请求跨度上限取 **100 kb**（实测 200 kb 也 OK，留 2× 安全余量）；
2. **校验实得长度**：解析 FASTA 头里的 `start:end` 与序列长度，**与请求不符即报错**，
   绝不静默接受——这正是 V3 的在线版；
3. **钳位检测**：若返回的区间末端等于染色体长度，说明请求越界，同样报错。

对本工具的实际影响很小：扩增子只有几百 bp，一次请求即够；只有"整条转录本"可能超过 100 kb
（ZNF8-201 全长 24 kb，安全）。

### 2A.4 缓存（内部优化，不是"本地参考文件"）

取消本地文件输入后，缓存的作用变成**纯粹的重复请求避免**——它存的是"从网上取回的切片"，
不是"用户提供的参考"。二者不能混为一谈：

| | 用户提供的 GTF/FASTA（已取消） | 本方案的缓存 |
|---|---|---|
| 来源 | 用户手工准备 | 程序从网上取回 |
| 完整性 | 全量（1.5 GB / 3 GB） | 只含用到的切片 |
| 用户是否需关心 | 需要（要下载、放对位置） | **不需要**（自动管理，可直接删） |

```text
${NANOAMP_CACHE_DIR:-~/.cache/nanoamp}/ref/
|-- regions/        # 按"染色体 + 对齐到 10 kb 栅格"命名，gzip 存储
|-- transcripts/    # 转录本结构 JSON（overlap/id 响应）
`-- meta.tsv        # 每项：来源 URL、取回时间、sha256、Ensembl release
```

| 规则 | 说明 |
|---|---|
| 区间栅格对齐 | 缓存键对齐到 10 kb，使邻近样本命中同一缓存（`01_data` 的 32 个样本只落在少数几个位点，收益很大） |
| 命中也要校验 | 命中缓存同样跑 V3 反切校验，避免"缓存被截断/被污染"后静默复用 |
| `--no-cache` | 强制重新拉取（排障用） |
| `--clear-cache` | 清空缓存（唯一面向用户的缓存操作） |
| **无离线模式** | 因不再有本地参考文件，`--offline` 已取消；网络不可用时**明确报错**并提示检查网络/代理，绝不静默降级 |
| 可追溯 | `meta.tsv` 记录 URL / 时间 / sha256 / Ensembl release（实测当前 **116**），并写入 `run_manifest.json` |

### 2A.5 来源优先级（只有两级，且都在程序内部）

```text
1. 本地缓存（~/.cache/nanoamp/ref/）      <- 程序自己之前取回的切片
2. 网络按需拉取（Ensembl REST；失败退 UCSC）
```

**没有"用户文件"这一级。** 因取消本地输入而产生的两个缺口，用下面的方式补：

| 缺口 | 处理 |
|---|---|
| 完全无网络（内网/气隙环境） | **明确不支持**（本版范围外）。报错时给出可达的替代方案：改用路线一（CDS 配置，只需用户知道 CDS 起止，不需要任何参考文件）。这是保留路线一的第二个理由（§2.1） |
| 发表/审计需要固定参考版本 | `run_manifest.json` 记录 **Ensembl release**（实测 116）、所用 URL 列表与每个切片的 sha256；报告注明"参考来自 Ensembl REST release N" |

> **风险提示**：取消本地文件后，**结果可复现性依赖 Ensembl 的 release 稳定性**。
> 缓解手段是 manifest 记录 release 号；若日后需要"钉死版本"（例如补审要求），
> 可以在那时再加回一个 `--ensembl-release` 参数指定历史版本（Ensembl 支持按 release 取），
> 这比让用户准备 4.5 GB 文件轻得多。

### 2A.6 与"GENCODE v50"的关系（必须显式声明）

需求方原本持有 **GENCODE v50**。取消本地输入后，需要注意两者关系：

| | GENCODE v50 | Ensembl REST（本方案实际使用） |
|---|---|---|
| ID 体系 | Ensembl 系（`ENST…` / `ENSG…`） | **完全相同** |
| 坐标组装 | GRCh38 | **完全相同** |
| 内容来源 | Ensembl + Havana 手工注释合并 | GENCODE 就是从它派生的 |
| 版本号 | release 50 | release **116**（实测） |

**结论：ID 与坐标可直接对齐，因此"取消本地 GTF"不会造成体系性错位。**
但仍需声明三条限制：

1. **版本可能不同**：GENCODE v50 与 Ensembl 116 的注释条目可能有增删改。若用户的
   结论需要严格对应 v50，应在报告中说明"参考为 Ensembl REST release 116"，
   而不是默认为 v50；
2. **实测验证过一致性**：在 ZNF8 位点上，Ensembl 返回的转录本 ID 与 `tag`（含
   `MANE_Select`）均符合 GENCODE 体系（§2D.1 表格），且自行翻译 CDS 与官方蛋白
   完全一致（F15）——说明这条链路没有 ID 或阅读框层面的错位；
3. **不使用非 GENCODE 体系的来源**：不采用 RefSeq、UCSC `ncbiRefSeq*` 等以 `NM_`/`NR_`
   编号的注释，也不采用 `knownGene` 的 `uc*` 编号，避免 ID 体系混杂。
   若 Ensembl 不可用而需退到 UCSC，**只用其序列端点**（`getData/sequence`），
   **不用其注释 track**。

---

## 2B. 联网接口契约（原"参考文件清单"已作废）

> **2026-09-23 定稿**：用户不再提供任何参考文件，本节因此从"要哪些文件"改为
> **"程序会调用哪些接口、各自提供什么、有什么坑"**。这是实现与排障的依据。

### 2B.1 接口清单（全部实测 HTTP 200 且内容已核对）

| # | 用途 | 端点（`https://rest.ensembl.org/…`） | 实测结果 | 必需 |
|---|---|---|---|---|
| 1 | 区间序列 | `sequence/region/human/<chr>:<s>..<e>:<strand>?content-type=text/x-fasta` | FASTA 头含 `GRCh38` 与坐标；**必须带 `content-type` 参数**（不带返回 415） | ✅ |
| 2 | 重叠转录本 | `overlap/region/human/<chr>:<s>-<e>?feature=transcript;content-type=application/json` | 返回 8 条，含 `id`/`external_name`/`biotype`/`is_canonical`/**`tag`（`MANE_Select`）**/`assembly_name`/`transcript_support_level`/`ccdsid` | ✅ |
| 3 | CDS 坐标块 | `overlap/id/<ENST>?feature=cds;content-type=application/json` | 24 个块，含 `start`/`end`/`strand`/**`phase`**——等价于 GTF 的 CDS 行 | ✅ |
| 4 | CDS 序列 | `sequence/id/<ENST>?type=cds;content-type=text/plain` | 1728 bp，首 `ATG`、末 `TAG` | ✅ |
| 5 | 官方蛋白 | `sequence/id/<ENST>?type=protein;content-type=text/plain` | 575 aa | ✅（V1 对拍用） |
| 6 | 外显子结构 | `overlap/id/<ENST>?feature=exon;content-type=application/json` | 用于拼接成熟 mRNA | ✅ |
| 7 | 版本核对 | `info/software?content-type=application/json` | `release: 116` | ✅（写入 manifest） |
| 8 | 备选序列源 | `api.genome.ucsc.edu/getData/sequence?genome=hg38;chrom=..;start=..;end=..` | HTTP 200 JSON；**注意 0-based、`chr` 前缀** | 仅作冗余 |

### 2B.2 为什么结构源必须是 Ensembl REST

原本可以"下载 GENCODE GTF 后在本地按区间查"，但**实测不可行**：

| 尝试 | 结果 |
|---|---|
| GENCODE `gencode.v50.primary_assembly.annotation.gtf.gz` 用 HTTP range 只取头部 | 是**标准 gzip（非 BGZF）**，取 4 KB 无法解压 → 无法流式部分读取 |
| 找 `.gtf.gz.tbi`（tabix 索引）做区间查询 | **HTTP 404**，GENCODE 不提供 |
| UCSC 的 GENCODE 派生 track（`knownGene`） | 能按区间查（返回 8 条，与 Ensembl 一致），但**ID 是 `uc*` / `knownGene` 体系**，不是 `ENST`，与 GENCODE 体系混杂 |

**结论：按区间取"GENCODE 体系"的结构信息，Ensembl REST 是唯一可行且 ID 体系一致的路径。**
这也是 §2A.6 第 3 条"退到 UCSC 时只用序列端点、不用注释 track"的原因。

### 2B.3 不使用、也不允许出现的来源

| 来源 | 是否使用 | 原因 |
|---|---|---|
| Ensembl REST | ✅ 主源 | ID 体系与 GENCODE 一致，支持按区间查 |
| UCSC 序列端点 | ✅ 备用（仅序列） | 冗余，防止 Ensembl 单点故障 |
| UCSC 注释 track（`knownGene` / `ncbiRefSeq*`） | ❌ | ID 体系不同（`uc*` / `NM_`），会造成混杂 |
| RefSeq / `NM_`·`NR_` 编号 | ❌ | 同上 |
| 用户提供的 GTF/FASTA | ❌ | **本版范围外**（需求方取消） |
| 本地基因组建索引（`.fai` + 本地 GTF 解析） | ❌ | 随本地输入一并取消，A5 的 local 分支也随之删除 |

### 2B.4 完全无网络时怎么办

本版**不支持离线**。此时唯一可用的注释路径是**路线一（CDS 配置）**——它只需要用户知道
扩增子上 CDS 的起止与阅读框，**不需要任何参考文件**，因此天然离线可用
（翻译只用 `Biostrings`）。这就是保留路线一的第二个理由（§2.1）。

---

## 2C. 扩增子自动定位（F11 的落地方式）

这是 GTF 路线的**入口环节**，已用真实数据验证可行。

### 2C.1 流程

```text
输入：公司共识序列（扩增子参考，208–1068 bp）+ 参考基因组 FASTA
1. 精确匹配：把全长共识序列在参考基因组上做精确字符串查找
   → ZNF8 WT 320 bp 实测 100% 命中 chr19:58,285,652-58,285,971（0 错配）
2. 精确匹配失败时（编辑过的克隆）：取 3–4 段 40 bp 探针分别定位
   → 实测 22 条克隆全部落在同一坐标，pid 91.6–100%
3. 仍失败时：局部比对（复用 pa_pairwise_alignment）+ 唯一性检查
4. 输出：{chrom, start, end, strand, identity, n_mismatch}
   → 要求"唯一命中"；多处命中即报错，不取第一条（对应 R11）
5. 写入 run_manifest.json，供人工复核一次
```

### 2C.2 为什么必须做这一步（而不是直接用扩增子坐标）

因为 **F12：扩增子是基因组型扩增子，跨越外显子/内含子边界**。实测那个 320 bp 区间
= 外显子2 上游内含子 65 bp + 外显子2 全部 127 bp + 下游内含子 128 bp。因此：

- 落在内含子部分的变异**根本不在成熟转录本里**，若按"扩增子坐标"当转录本切片会得到错误蛋白；
- 落在外显子2 的部分位于某个转录本 CDS 内（127 bp）；
- 想判断"是移码还是 missense"，必须知道每个变异落在**基因组的哪一段**（CDS / UTR / 内含子 /
  剪接区），而这只有先定位到基因组坐标才可能。

### 2C.3 蛋白注释的正确路径（因 F12 而修正）

不要"从扩增子里切 CDS"。正确路径是：

```text
1. 用参考基因组 + GTF 拼接出该转录本的成熟 mRNA（exon 顺序拼接，负链反向互补）
2. 定位该转录本的 CDS 区间，得到参考 CDS 与参考蛋白
3. 把变异按基因组坐标映射到 mRNA 坐标；落在内含子的变异记为 intron 后果、不参与翻译
4. 把落在 CDS 的变异应用到参考 CDS → 突变 CDS → 翻译 → 与参考蛋白比对 → 蛋白级描述
```

这条路径同时解决了 §3.3 里"从单倍型取 CDS"的做法在基因组型扩增子上失效的问题
（原做法假设扩增子 = 转录本切片，已被 F12 证伪）。

---

## 2D. 转录本选择：程序内选择 + `All`

**需求方已确认：不做"委托方指定转录本"，改为程序内让用户自己选，并提供 `All` 选项。**
这条设计同时消化了两个缺口：没有 MANE Select 摘要（2B.2 第 5 项）、没有确切基因名（第 6 项）。

### 2D.1 候选清单从哪来

扩增子定位到基因组坐标后（§2C），用该坐标反查重叠转录本。**两个来源，同一份数据结构**：

| 来源 | 端点 | 提供 |
|---|---|---|
| **默认（联网）** | `overlap/region/human/<chr>:<s>-<e>?feature=transcript` | `id`、`external_name`、`biotype`、`is_canonical`、**`tag`（含 `MANE_Select`）**、`assembly_name`、`transcript_support_level`、`ccdsid`、`strand`、`start`、`end` |
| 可选（本地 GTF） | 解析 `transcript` / `exon` / `CDS` 行 | 同上（`tag` 来自 GTF 属性列） |

两者都归一化成同一张候选表：

```text
重叠的所有 transcript
  ├─ transcript_id / external_name（如 ENST00000621650 / ZNF8-201）
  ├─ 所属 gene（gene_id / gene_name）
  ├─ biotype（protein_coding / lncRNA / NMD ...）
  ├─ 与该扩增子重叠的 exon 数、CDS 重叠长度、UTR 重叠长度
  ├─ 优先级标记：tag 含 MANE_Select / Ensembl_canonical；is_canonical
  ├─ transcript_support_level、ccdsid（额外的可信度线索）
  └─ CDS 总长度、蛋白长度
```

**实测样例**（ZNF8 位点，8 条重叠转录本中的蛋白编码部分）：

| transcript | 名称 | canonical | tag | CDS 重叠 |
|---|---|---|---|---|
| ENST00000621650 | ZNF8-201 | ✅ | `gencode_basic, Ensembl_canonical, gencode_primary,` **`MANE_Select`** | 127 bp |
| ENST00000914383 | ZNF8-202 | — | `gencode_basic` | 0 bp |
| ENST00000982240 | ZNF8-203 | — | `gencode_basic` | 127 bp |
| ENST00001117421 | ZNF8-204 | — | `gencode_basic` | 0 bp |
| ENST00001142519 | ZNF8-205 | — | `gencode_basic, ens_canon_extended` | 0 bp |

**关键**：候选来源是**数据本身**（坐标反查），不依赖基因名，因此"ZNF8 有 5 个蛋白编码
转录本、且 CDS 重叠长度不同"这一事实会自然浮现给用户，而不是被文件名的推断掩盖（F13）。
另外注意上表里 **ZNF8-202/204/205 的 CDS 重叠为 0 bp**——若用户误选它们，全部变异都会
被判为 `outside_cds`；把这一列摆在界面上（§2D.2）正是为了避免这种"看起来跑通了但结论无意义"。

### 2D.2 选择界面（CLI 与 TUI 各一套，共享同一份候选清单）

**CLI（非交互，可脚本化）**

```text
--transcript ENST00000621650          指定单个转录本
--transcript all                       全部重叠转录本都注释
--list-transcripts                     只打印候选清单与各自后果，不跑分析（便于先看再选）
```

**TUI / 桌面界面（`TUI_plan.1.md` 的"参数页"）**

在注释参数区增加一个多选列表：

```text
┌─ 转录本（该扩增子重叠 5 个） ──────────────────────────────┐
│ [ ] ENST00000621650  ZNF8-201  575 aa  CDS 重叠 127 bp  ★canonical │
│ [ ] ENST00000982240  ZNF8-203  105 aa  CDS 重叠 127 bp            │
│ [ ] ENST00000914383  ZNF8-202  584 aa  CDS 重叠   0 bp            │
│ ...                                                              │
│ [ All ] 全选        [ None ] 清空      [ ★ ] 仅选 canonical/MANE   │
└──────────────────────────────────────────────────────────────────┘
```

- 默认选中 **`MANE_Select`** 那一条（实测 API 直接提供该 tag，§2A.2）；若该位点没有 MANE
  标记，则退到 `Ensembl_canonical`；两者都没有时**默认不选**并提示用户手动选，
  避免我们替用户做权威判断；
- `All` 一键全选，用于"我还不确定目标转录本"的探索场景；
- 每行显示 **CDS 重叠长度**，让"这个转录本到底覆不覆盖我的靶点"一眼可见（这正是 F12/F13
  暴露出来的关键信息）。

界面细节遵循 `TUI_plan.1.md` 的既有约定（键位、纯函数渲染、无 TTY 降级为行式菜单）。

### 2D.3 `All` 模式的输出约定

`All` 会显著增加输出量，必须约定清楚，否则结果不可读：

| 项 | 约定 |
|---|---|
| `annotation.tsv` 布局 | 每个单倍型 × 每个所选转录本一行；新增 `transcript_id` / `gene_name` / `is_canonical` 列 |
| 行的顺序 | 先按单倍型 `count` 降序，同一单倍型内按"后果严重度"降序，再按 `transcript_id` |
| 总体结论 | 另出一列 `consequence_any_transcript`：取所有转录本里**最严重**的后果（§3.5 优先级），方便一眼看"最坏情况" |
| 一致性提示 | 若同一变异在不同转录本下后果不同，另出 `transcript_conflict = TRUE` 并列在 `qc.tsv` 计数中——**这是"选错转录本"最直观的报警**（R12） |
| 是否需要权威选择 | 报告里明确写"未指定权威转录本，以下为全部重叠转录本的结果"，不暗示其中某一个是"对的" |

### 2D.4 MANE Select 现在可以拿到，`All` 的定位随之变化

**2026-09-23 更正**：上一版写"MANE 要不到，只能用 `All` 补偿"。实测 Ensembl 的
`overlap/region` 返回的 `tag` 字段**直接包含 `MANE_Select`**（§2A.2），所以：

| | 上一版 | 现在 |
|---|---|---|
| MANE Select | ❌ 要不到（列为缺口） | ✅ API 直接给，**默认选项可落在 MANE Select 上** |
| `All` 的作用 | 必需的补偿手段 | **降级为探索性选项**：当用户不确定目标转录本、或想看"若按别的转录本会怎样"时使用 |

`All` 仍然保留且仍然有用（尤其配合 `transcript_conflict` 报警），但**不再是唯一保障**。
默认路径现在是"MANE Select（有则用）→ 否则 canonical → 否则让用户选"，比上一版更确定。

### 2D.5 默认行为（必须显式，不能隐式）

| 情况 | 行为 |
|---|---|
| 未传 `--transcript` 且未在界面选择 | **报错并打印候选清单**，提示用 `--list-transcripts` 查看后指定；**不静默挑一个** |
| 传了 `all` | 全量注释（§2D.3） |
| 传了不存在的 `ENST` | 报错，并提示该扩增子实际重叠的转录本 |
| 候选为空（扩增子不落在任何转录本内） | 只能给"基因间区"结论，明确说明 |

> **记录**：因委托方侧确认 MANE / 基因名 / 引物 / 人工样本"基本要不到"（2B.2），
> 本章的 `All` 设计从"便利功能"升级为**必需的正确性保障手段**。

## 3. D1：功能分类设计

### 3.1 两层注释（对应 §7.4 的明确要求）

§7.4 要求"不要把每个变异的注释简单拼接"。因此：

```text
第 1 层  变异级：每个变异单独判 → 写入 variants.tsv 新列（便于按位点筛）
第 2 层  单倍型级：整条单倍型的蛋白后果 → 主交付（回答"最终蛋白变成什么"）
         参考 CDS → 翻译 → 参考蛋白
         单倍型 CDS → 翻译 → 突变蛋白
         两者全局比对 → 结构化描述
```

### 3.2 变异级分类规则（实现 §7.3）

| 顺序 | 条件 | `Consequence` |
|---|---|---|
| 1 | 落在 CDS 之外但在扩增子内 | `outside_cds` |
| 2 | 落在 `cds.start`/`cds.end` 边界 ±1–2 bp | `splice_region`（有内含子边界时细分为 `splice_donor`/`splice_acceptor`） |
| 3 | 与 CDS 起点重叠且破坏起始密码子 | `start_lost` |
| 4 | indel 长度（含 `delregion`）`% 3 != 0` | `frameshift` |
| 5 | indel 长度 `% 3 == 0` | `inframe_insertion` / `inframe_deletion` |
| 6 | SNV：密码子变但氨基酸不变 | `synonymous` |
| 7 | SNV：氨基酸变且新密码子是终止 | `stop_gained`（提前终止 / nonsense） |
| 8 | SNV：原为终止、变异后不是 | `stop_lost` |
| 9 | SNV：氨基酸变，其他 | `missense` |

要点：顺序不可交换（`frameshift` 必须优先于任何密码子级判断）；`delregion` 是仓库特有的
"缺失区段"类型（`R/variants.R::canonicalize_deletions`），按**区段整体**判断；落入 CDS 的
变异必须先换算到 **CDS 坐标系**（考虑 `strand` 与 `frame`）再定位密码子——该换算要有独立纯函数。

委托方点名的三项对应：**移码 → `frameshift`**、**提前终止 → `stop_gained`**、
**missense → `missense`**，均在表中显式可得。

### 3.3 单倍型级蛋白注释

```text
1. 按 §2.3 从单倍型序列取出 CDS 子序列
2. 长度校验，不满足则 cds_ok = FALSE 并跳过（不硬翻）
3. 翻译（歧义碱基处理见 §3.4）
4. 与参考蛋白全局比对（复用 pa_pairwise_alignment，F8）
5. 生成结构化描述
```

`protein_change` 采用 **HGVS 风格但显式声明非合规**：

```text
p.Glu23Lys            missense
p.Glu23Ter            stop_gained（提前终止）
p.Glu23LysfsTer17     frameshift，且给出新的终止位置
p.Ter45LeufsTer8      stop_lost
p.(Met1?)             start_lost
```

### 3.4 两个必须自己处理的边界（源自 F7）

1. **部分密码子**：`translate()` 静默丢弃尾部不足一密码子的碱基。注释层必须**自己截断并
   记录**被丢弃碱基数，而不是静默接受；
2. **歧义碱基**：含 `N` 等使 `translate()` 报错。策略：CDS 内出现歧义碱基 → 标记
   `cds_ambiguous_base`、记录位置、跳过蛋白注释。**不允许**把 `N` 当 `A` 静默处理。

### 3.5 总体后果优先级

单倍型可能含多个变异，`consequence` 取最严重者（常量写入代码与文档，不做隐式排序）：

```text
frameshift > stop_gained > stop_lost > start_lost
           > inframe_insertion / inframe_deletion
           > missense > synonymous > outside_cds
```

---

## 4. 依赖：零新增（P0 全部路线）

| 能力 | 复用现有 | 新增依赖 |
|---|---|---|
| 翻译 / 遗传密码 | `Biostrings::translate()`、`GENETIC_CODE`、`getGeneticCode()`（F6） | 否 |
| 蛋白比对 | `pa_pairwise_alignment()`（`R/zzz.R`，F8） | 否 |
| 反向互补 | `reverse_complement()`（`R/utils.R`） | 否 |
| 序列读取 / md5 | `read_reference()`、`safe_md5()`（`R/io.R`） | 否 |
| ~~GTF 解析~~ | 已随本地输入取消；结构改从 REST JSON 解析（`jsonlite`） | 否 |
| 配置解析 | `jsonlite::fromJSON`（已是现有依赖） | 否 |
| **HTTP 请求（联网模式）** | **`curl` 外部命令**（本机实测可用；可复用 `03_dependence` 的外部工具解析机制）或 R 自带 `url()` | 否 |
| **JSON 响应解析** | `jsonlite::fromJSON`（已是现有依赖） | 否 |
| YAML 配置（可选） | 仅当 `requireNamespace("yaml")` 时启用 | 可选 |

**HTTP 走哪条路**：按可用性依次回退——

1. 系统 `curl`（实测本机可用，且 `03_dependence` 已有"外部工具优先解析"机制可复用）；
2. R 自带 `url()` + `readLines()`（无外部依赖，错误处理较弱）；
3. 可选包 `curl` / `httr2`——**不引入**，避免动依赖清单。

因此**联网模式同样零新增 R 包依赖**，可以沿用报告 9/10 建立的分发路径，
**安装文档的依赖清单不需要改动**。

---

## 5. 输出契约

### 5.1 `variants.tsv` 追加列（变异级）

保持既有 12 列的名称与顺序不变（公司表对照脚本依赖它），仅在其后追加：

```text
... Filter_Status  Filter_Reason  Consequence  Codon_Ref  Codon_Alt  AA_Ref  AA_Alt  CDS_Pos  Exon
```

### 5.2 新文件 `annotation.tsv`（单倍型级，主交付）

| 列 | 说明 |
|---|---|
| `haplotype_id` | 关联 `haplotypes.tsv` |
| `count` / `proportion` | 从 `haplotypes.tsv` 带过来，便于排序阅读 |
| `cds_ok` | FALSE 表示边界/歧义等异常，后续列为空 |
| `cds_length` | 单倍型 CDS 长度 |
| `ref_protein_length` / `alt_protein_length` | 蛋白长度 |
| `n_aa_changed` | 氨基酸替换数 |
| `protein_change` | 结构化描述（§3.3） |
| `consequence` | 单倍型总体后果（§3.5） |
| `is_synonymous` | 全部变异同义且无 indel |
| `ref_protein` / `alt_protein` | 可选，`--annotation-proteins` 时输出，默认关闭以免文件过大 |

### 5.3 `qc.tsv` 追加指标

```text
annotation_enabled  annotation_name  annotation_source(amplicon|transcript)
genetic_code  cds_length_nt  cds_length_aa
n_haplotypes_annotated  n_haplotypes_skipped
n_frameshift  n_stop_gained  n_stop_lost  n_start_lost
n_missense  n_synonymous  n_inframe
```

### 5.4 `run_manifest.json` 追加段（可复现性）

```json
"annotation": {
  "enabled": true,
  "source": "amplicon",
  "config_path": "configs/znf8.json",
  "config_sha256": "...",
  "config": { "... 原文 ..." },
  "genetic_code": "Standard",
  "cds": {"start": 55, "end": 320, "strand": "+", "frame": 0},
  "gtf_sha256": null
}
```

GTF 模式下同时记录 `gtf_sha256` 与 `transcript_id`，否则结论无法追溯。

---

## 6. CLI 接口

```text
--annotate-config PATH   启用功能注释（JSON 配置）；不传则完全不启用

# 参考来源（§2A）：只走联网按需拉取，无本地文件输入
--cache-dir PATH                 覆盖缓存目录（默认 ~/.cache/nanoamp/ref）
--no-cache                       忽略缓存，强制重新拉取（排障用）
--clear-cache                    清空缓存后退出（唯一面向用户的缓存操作）
--species homo_sapiens           默认人；用于 Ensembl 端点
--assembly GRCh38                默认 GRCh38（与 GENCODE 体系对齐）
--ensembl-release N              可选：钉住 Ensembl release（默认最新；§2A.5 的可复现手段）

# 转录本选择（§2D）
--transcript ENST...|all         选择转录本；不传且界面未选则报错并列出候选
--list-transcripts               仅列出候选转录本与各自后果，不跑分析

# 输出
--annotation-proteins            在 annotation.tsv 中输出 ref/alt 蛋白序列
--annotation-detail              额外输出变异级明细（默认只出单倍型级）
```

行为约定：

| 场景 | 行为 |
|---|---|
| 未传 `--annotate-config` | **完全走现有路径，输出与现在逐字节一致**（P0 验收项） |
| 配置文件不存在 / JSON 非法 | 明确报错，退出码 1（沿用现有约定） |
| `genetic_code` 无法解析 | 报错并列出 `GENETIC_CODE_TABLE` 的合法取值 |
| CDS 区间超出参考长度 | 报错 |
| `reference_md5` 不符 | 报错并提示"配置是为另一个参考写的"（防止误用 wt 参考） |
| 未选转录本 | 报错 + 打印候选清单，提示先跑 `--list-transcripts`（**不静默挑一个**，§2D.5） |
| `--transcript all` | 对全部重叠转录本注释，并输出 `consequence_any_transcript` 与 `transcript_conflict`（§2D.3） |
| 指定的 `ENST` 不存在 | 报错并列出该扩增子实际重叠的转录本 |
| 扩增子不落在任何转录本内 | 只给"基因间区"结论，并明确说明 |
| V1 参考蛋白对拍失败 | **中止**并报错（§7.5）——说明 CDS/phase/链向处理有错 |
| 网络不可用（DNS/超时/HTTP 5xx） | 重试有限次后报错，提示检查网络/代理；**不静默降级为非注释结果**；并提示可用路线一（CDS 配置）离线完成（§2B.4） |
| Ensembl 不可用但 UCSC 可用 | 序列走 UCSC 端点；**结构类信息无法替代**，若结构缺失则报错（§2B.3） |
| `--ensembl-release` 指定的版本不存在 | 报错并列出可用 release |
| Ensembl 返回长度与请求不符（§2A.3 静默截断） | 报错（V3 在线版），提示可能是区间越界或触发上限 |

---

## 7. 测试与验收

### 7.1 为什么只能靠合成数据（源自 F4）

公司交付表没有任何功能注释信息，**不存在"复刻公司注释"这条验收路径**。验收必须建立在
"我们构造、我们已知答案"的数据上——这与现有 `test-core.R` 的合成数据做法一致。

### 7.2 合成用例矩阵

| 用例 | 构造 | 期望 |
|---|---|---|
| 参考一致 | 无变异 | 无蛋白改变 |
| 同义 SNV | 改密码子第三位不换氨基酸 | `synonymous` |
| 错义 SNV | 改密码子第一位 | `missense` + 正确 `p.XaaN Yaa` |
| **提前终止** | 改出 `TAA`/`TAG`/`TGA` | `stop_gained` |
| 终止丢失 | 终止密码子改为氨基酸 | `stop_lost` |
| 起始丢失 | 破坏首 ATG | `start_lost` |
| **移码** | 单碱基插入或缺失 | `frameshift` + `fsTer` 位置 |
| 整码缺失 / 插入 | 缺/插 3 bp | `inframe_deletion` / `inframe_insertion` |
| **多变异组合** | 两个单独都是 missense，组合后提前终止 | **组合后果**，且与"逐条拼接注释"结论**不同**（§7.4 要防的错误） |
| 非 3 倍数参考 | 用真实的 208 bp 参考（F2） | `outside_cds` 正确、注释不越界 |
| CDS 上游 indel | CDS 之前插 1 bp | 引物锚定模式下仍给出正确蛋白 |
| 边界异常 | indel 跨越 CDS 边界 | `cds_ok = FALSE` + 明确原因 |
| 歧义碱基 | CDS 内放 `N` | `cds_ambiguous_base`，不产出假蛋白 |
| 负链 CDS | `strand = "-"` | 与正链镜像构造结果一致 |
| 非标准遗传密码 | `genetic_code = "2"` | `TGA` 译作 `W` 而非终止 |
| 部分密码子 | CDS 长度非 3 的倍数 | 记录被丢弃碱基数，不静默 |
| **GTF 模式** | 构造一个小转录本 + GTF（含一个内含子） | CDS 拼接正确；内含子内变异判为 `intron`；UTR 判为 `5_prime_UTR`/`3_prime_UTR` |

### 7.3 回归与不变性

| 检查 | 判据 |
|---|---|
| 未启用注释 | `haplotypes.tsv`/`variants.tsv`/`qc.tsv` 与基线**逐字节一致** |
| 启用注释 | 既有三张表的**原有列**逐字节一致，仅追加列/追加文件 |
| 全量功能测试 | 168/168 仍全部 `ok` |
| `R CMD check` | Status: OK |
| 变异集合一致性 | 与公司表的重合率不因注释改变（仍为 22/23 满分） |

### 7.4 文档

`shared/docs/output_schema.md`（补契约）、`02_code/README{,-CN}.md`（新增"功能注释"一节 + 后果类型对照表）、
`02_code/cli/README.md`（新参数）、`02_code/ARCHITECTURE.md`（目录图）、
`configs/README.md`（教用户如何取得 CDS 坐标 / 如何选转录本）。

### 7.5 没有外部基线时的三重自检（因 2B.2 的 D 项要不到而新增）

外部基线**全部缺失**：MANE Select 没有、引物没有、人工核对样本没有、公司表不含功能注释（F4）。
因此正确性必须靠程序内部三重复核，且**每次运行都执行**（不是可选开关）：

| # | 自检 | 判据 | 失败处理 |
|---|---|---|---|
| **V1** | **参考蛋白对拍** | 用我们的 GTF+FASTA 拼接并翻译出的参考蛋白，与 GENCODE 官方 `gencode.v50.*.pc_translations.fa`（或 Ensembl `protein.faa`）逐条一致 | 不一致即**中止并报错**，说明 CDS/phase/链向处理有错——这是最强的一道闸 |
| **V2** | **CDS 结构自检** | 每条所用转录本：CDS 长度能被 3 整除、首密码子为 `ATG`、末密码子为终止密码子、CDS 坐标落在 exon 并集内（按基因组坐标精确运算，不用 min/max 近似——见下文教训） | 不通过则拒绝注释该转录本并说明原因 |
| **V3** | **扩增子定位自检** | 精确匹配得到的坐标**反向切片**后必须与输入序列 `identical()`（F11 已用此法双重验证）；局部比对则要求 identity ≥ 阈值且**唯一命中** | 不唯一或不达阈值即报错，不静默采用 |

> **一条实际教训**：本方案起草过程中，我第一版用
> `min(end, exon_end) - max(start, exon_start) + 1` 判断"变异是否在 CDS 内"，结果把
> 内含子里的区间误判为 CDS（因为该公式无法表达"区间落在 exon 之间的空隙里"）。
> V2 因此要求**按区间集合精确运算**（先与 exon 求交，再与 CDS 求交），并有专门的
> "跨外显子边界"与"完全落在外显子间隙"用例（已列入 §7.2）。

**结论**：在拿不到任何外部基线的前提下，V1–V3 是唯一能证明"坐标与阅读框没错"的手段，
因此它们属于 **P0 验收项**，而非"nice to have"。

---

## 8. 目录与文件规划

```text
02_code/
|-- R/
|   |-- ref_resolver.R       # 【新】参考解析层：缓存 + 联网两级来源、分块与长度校验、meta 记录
|   |-- ref_online.R         # 【新】Ensembl 客户端：区间序列、重叠转录本、CDS 块、CDS/蛋白；UCSC 仅序列兜底
|   |-- annotate_config.R    # 配置解析与校验（genetic_code、reference_md5、ensembl-release、transcript）
|   |-- annotate_cds.R       # CDS 定位：坐标 / 负链 / frame（两条路线共用）
|   |-- annotate_locate.R    # 扩增子定位（§2C）：精确匹配 -> 探针 -> 局部比对 + 唯一性检查
|   |-- annotate_map.R       # 坐标三重映射：扩增子→基因组→转录本→CDS（纯函数，重点单测）
|   |-- annotate_translate.R # CDS 切片、部分密码子、歧义碱基、翻译、与参考蛋白对拍
|   |-- annotate_variant.R   # 变异级分类（§3.2 规则表）
|   `-- annotate_haplotype.R # 单倍型级蛋白注释与比对（§3.3）
|-- tests/testthat/
|   |-- test-annotate.R          # §7.2 全部用例
|   `-- test-annotate-genome.R   # FASTA+GTF 端到端：用构造的小基因组/小 GTF 跑通
|-- shared/docs/output_schema.md     # 增补契约
|-- shared/params/default_params.json# 增补 annotate / annotation_config
`-- configs/
    |-- example_cds.json         # 路线一（用户提供 CDS 坐标；离线可用，作退路）
    |-- example_online.json      # 路线二（联网按需拉取；无需任何参考文件）
    `-- README.md
```

**缓存目录（仓库外，不在 Git 内）**：

```text
${NANOAMP_CACHE_DIR:-~/.cache/nanoamp}/ref/
|-- regions/        # 按染色体 + 对齐到 10 kb 栅格的区间命名，gzip 存储
|-- transcripts/    # 转录本结构 JSON（overlap/id 响应）
`-- meta.tsv        # 每项：来源 URL、取回时间、sha256、Ensembl release
```

**没有需要用户放置的参考文件**（本地输入已取消）。缓存目录在仓库外（§2A.4），
不进 Git，可直接删除；`.gitignore` 仍保留 `refs/`、`*.fa`、`*.fai`、`*.gtf` 等条目，
以防临时文件被误提交。

**性能注意**：单次请求量级为几百 bp–几十 kb；配合 10 kb 栅格缓存后，同一批样本通常只触发
个位数次网络请求。实测限流为 **55,000 次/小时**，远高于实际需求（32 个样本约需 ≤ 10 次／样本）。

---

## 9. 分阶段实施计划

| 阶段 | 内容 | 对应交付 | 人日 | 判据 |
|---|---|---|---|---|
| **A1** | 配置解析 + CDS 定位（坐标 / 负链 / frame / 边界语义） | D2 路线一 | 2–3 | 配置与定位单测通过；边界语义有显式用例 |
| **A2** | 翻译层：部分密码子、歧义碱基、非标准遗传密码 | D1 基础 | 1–2 | §3.4 三个边界均有测试 |
| **A3** | 变异级分类（§3.2 规则表，含 `delregion` 与 CDS 坐标换算） | **D1** | 2–3 | §7.2 中除组合与 GTF 外全部通过 |
| **A4** | 单倍型级蛋白注释与比对（优先级、`protein_change`） | **D1** | 3–4 | §7.2 全部通过（含组合用例） |
| **A0** | **参考解析层（§2A/§2B）**：Ensembl 客户端（区间序列、重叠转录本、CDS 块、CDS/蛋白）+ 缓存（10 kb 栅格、`meta.tsv`）+ 区间分块与长度校验 + UCSC 序列兜底 | D2 基础设施 | **3–4** | 长度不符会报错；同一区间二次运行命中缓存不联网；缓存可清空后重建 |
| **A5** | 坐标与结构：把 REST 返回的转录本/CDS 块/外显子归一为统一结构；**扩增子定位（§2C）**；坐标三重映射；UTR/内含子/剪接判定 | **D2 路线二** | **4–7** | 小规模构造数据端到端通过；内含子/UTR/边界判定正确 |
| **A5b** | **V1–V3 三重自检（§7.5）**：参考蛋白对拍、CDS 结构自检、定位反切校验 | D2 正确性 | **2–3** | V1 与 GENCODE 官方翻译逐条一致；V2/V3 有专门用例（含"落在外显子间隙"） |
| **A5c** | **转录本候选清单 + 选择接口（§2D）**：坐标反查候选、CDS 重叠长度、`--list-transcripts`、`--transcript all`、`All` 输出布局 | D2 交互 | **2–3** | 默认不选时报错并列出候选；`All` 输出含 `consequence_any_transcript` 与 `transcript_conflict` |
| **A6** | 输出接线：`variants.tsv` 新列、`annotation.tsv`、`qc.tsv`、manifest | D1+D2 | 1–2 | §7.3 前两条不变性通过 |
| **A7** | CLI 参数 + 文档 + `configs/` 示例（含 `refs/` 放置说明） | D1+D2 | 1–2 | 端到端示例可复现 |
| **A8（可选）** | 转录本多选界面接入 TUI（§2D.2 的草案） | UI | 2–3 | 依赖 `TUI_plan.1.md` 的排期，可与 A5c 共用候选清单数据 |

**最小可用交付 = A0–A7 ≈ 19–30 人日**（A0 参考解析层 3–4 人日为联网模式新增；
A5 因取消 local 分支从 5–8 降到 4–7），即覆盖"移码/提前终止/missense"（D1）与
"连接 GTF"（D2）；**A8 另计**，属 UI 范畴。

> **A0 的 3–4 人日换来什么**：使用者**不做任何准备**（不必下载 4.5 GB、不必放对路径），
> 打开就能注释；代价是引入网络依赖与"版本漂移"这一新风险（R17、R18），
> 由 manifest 记录 release + 缓存 + 明确报错来兜。

> 相比上一版（A1–A7 ≈ 15–25 人日），本轮新增 **A5b（2–3 人日）+ A5c（2–3 人日）**，
> 原因有二：
> - **A5b**：委托方侧的 MANE / 引物 / 人工样本**全部要不到**（2B.2），外部基线为零，
>   因此 V1–V3 自检从"锦上添花"变成唯一能证明坐标与阅读框正确的手段；
> - **A5c**：转录本选择改由程序承担（§2D）。其中 `All` 模式不只是便利功能，而是
>   替代 MANE Select 的**正确性保障**（R12）。
>
> 若希望压缩工期，可考虑：先做 A5c 的 CLI 部分（`--transcript` / `--list-transcripts`），
> 把 `All` 的输出布局延后；但**不建议砍 A5b**。
>
> 排序理由：A1–A4 是 D1，无论走哪条坐标路线都必须有；A5 是 D2 的坐标来源；A5b 必须在
> A5 之后立刻做（否则后面所有结论都建立在未验证的坐标上）。

---

## 10. 风险与对策

| # | 风险 | 影响 | 对策 |
|---|---|---|---|
| R1 | CDS 坐标或阅读框写错 | 整份注释系统性偏移且看起来"合理" | 输出 `Codon_Ref`/`Codon_Alt`/`AA_Ref`/`AA_Alt` 供人工抽检；`reference_md5` 强校验；`configs/README.md` 给出自检清单（首密码子应为 ATG、末密码子应为终止） |
| R2 | 用户没有 GTF，也不会填 CDS 坐标 | 功能实际不可用 | 两条路线都可走；文档给出"如何取得坐标"的具体步骤；报错信息给修复指引 |
| R3 | 负链 + frame 组合换算错误 | 静默错误 | 独立坐标换算纯函数 + 正/负链镜像用例对拍（§7.2） |
| R4 | 多变异组合按位点拼接 → 错结论 | 正是 §7.4 警告的错误 | 单倍型级注释为主交付；专门构造"组合 ≠ 拼接"的用例 |
| R5 | 歧义碱基 / 部分密码子被静默处理 | 假蛋白序列 | §3.4 显式标记并跳过，绝不猜测 |
| R6 | CDS 被 indel 跨越致边界错位 | 蛋白注释错误 | 引物锚定优先；边界异常时 `cds_ok = FALSE` 而不硬翻 |
| R7 | 注释改变核心输出 | 破坏既有回归 | 关闭时逐字节一致（P0 验收）；开启时只追加 |
| R8 | GTF 解析过于简化（只读 CDS/exon） | 复杂 GTF 上出错 | 明确声明支持范围；遇到不支持的 feature 组合时**报错而非猜测**；记录 `gtf_sha256` |
| R9 | 误用另一个参考（self vs wt） | 结果错乱 | `reference_md5` 校验 + 长度校验，报错并指出可能用错参考 |
| **R10** | **参考基因组与 GTF 不匹配**（组装不同 / `chr1` vs `1` 命名 / 非 primary assembly） | 坐标系统性错位，注释全错却看似合理 | **V1 参考蛋白对拍**（§7.5）会在这种情况下直接失败并中止——这是最强闸门；另加染色体名一致性检查；记录两个文件的 sha256 |
| **R11** | **扩增子定位错误**（局部比对落到旁系同源区、多处命中） | 落到错误基因/转录本 | 要求**唯一命中**，多处命中即报错而非取第一条；精确匹配优先（F11 实测可 100% 命中）；**V3 反切校验** |
| **R12** | **选错转录本**（全基因组 GTF 有约 20 万转录本；F13 实测同一位点在 ZNF8-201/203 下语境不同） | 同一变异给出不同后果 | ①`--transcript` **必填或界面必选**，绝不静默挑一个；②提供 **`All` 全量注释**（§2D）；③输出 `transcript_conflict` 报警；④manifest 记录所用转录本清单。**注意：因拿不到 MANE Select（2B.2），本条无法靠"权威转录本"缓解，只能靠 `All` + 冲突报警** |
| **R13** | 参考基因组 3 GB 全量载入导致内存爆掉 | 功能不可用 | 实现 `.fai` 式区间取序 + 按需载入单条染色体；GTF 按坐标/`transcript_id` 预过滤而非全量 `fread` |
| **R14** | **完全没有外部正确性基线**（MANE、引物、人工核对样本、公司功能注释全部缺失——2B.2 + F4） | 错误可能长期不被发现 | **V1–V3 三重自检设为 P0 每次运行都执行**（§7.5）；输出 `Codon_*`/`AA_*` 供人工抽检；报告显式声明"本结果未经外部基线验证" |
| **R15** | `All` 模式输出行数膨胀（单倍型 × 转录本） | 结果不可读、文件过大 | 按 §2D.3 约定排序与列布局；`consequence_any_transcript` 提供一眼可读的最坏情况；`qc.tsv` 给出计数；必要时 `--annotation-detail` 才展开变异级 |
| **R16** | **联网取序被静默截断**（实测：请求 500 kb 只回 331,965 bp，HTTP 仍 200；5 Mb 还会被钳到染色体末端） | 用缺了尾巴的序列做注释 → 坐标/蛋白错误，且**完全不报警** | 单次请求上限设 **100 kb**；**校验实得长度与请求一致**、并检测"末端等于染色体长度"的钳位；不符即报错（§2A.3、V3 在线版） |
| **R17** | **在线来源版本漂移**（Ensembl 升级 release 后注释可能变化） | 同一分析在不同时间得到不同注释，不可复现 | `run_manifest.json` 记录 Ensembl release（实测当前 116）与每个切片的 sha256；提供 `--ensembl-release` 钉住版本；报告中标注参考来源（§2A.6） |
| **R18** | 网络不可用 / API 变更 / 限流 | 功能不可用或结果缺失 | 缓存优先（§2A.4，命中即不联网）；**明确报错而非静默降级**，并提示改用路线一（CDS 配置）离线完成；限流实测 55,000 次/小时（远超需求）；API 结构变更时给出"改用路线一"的兜底指引 |
| **R20** | 取消本地文件后，**内网/气隙环境完全无法使用路线二** | 这部分用户拿不到 GTF 路线的注释 | 明确写入文档"本版不支持离线"；提供**路线一（CDS 配置）**作为离线路径（只需 CDS 坐标，不用任何参考文件）；若日后此类需求变强，再考虑加回 `--gtf/--genome`（实现上 A0/A5 只需恢复一个分支） |
| **R19** | 联网取到的序列与公司参考不完全一致（SNP、indel、或参考本身来自质粒/编辑后序列） | 定位错位或错配被当成变异 | §2C 要求记录 identity 与 mismatch 数；**精确匹配优先**；局部比对需唯一命中且达阈值；不做"模糊匹配后静默使用" |

---

## 11. 待确认问题

> 2026-09-23 **定稿**：三项决定已确认——① `All` 输出用"每单倍型 × 每转录本一行 + 两个汇总列"
> （§2D.3）；② 保留路线一（CDS 配置）作为退路（§2.1）；③ **取消本地 GTF/FASTA 输入，
> 参考信息只走联网**（§2A/§2B）。
> **结论：无阻塞项、无待委托方提供项，方案可以进入实现。** 以下仅剩实现期的细节确认。

**A. 已全部确定，无需再问**

| 项 | 结论 |
|---|---|
| 参考文件 | **不需要任何文件**（联网按需拉取；§2A） |
| 基因组组装 | **GRCh38**（与 GENCODE/Ensembl 体系一致） |
| 扩增子坐标 | 程序自动定位（§2C，F11 实测可 100% 命中） |
| 转录本选择 | 程序内选择，默认落在 `MANE_Select`（实测 API 提供），支持 `All`（§2D） |
| GTF 来源约束 | **只允许 GENCODE/Ensembl 体系**；不用 RefSeq、不用 UCSC 注释 track（§2A.6、§2B.3） |
| 各靶点基因名 | 由坐标反查，不依赖文件名的推断 |

**B. 实现期需要你确认的细节**

1. **`--ensembl-release` 的默认值**：默认取"最新"（实现时是 116），还是钉在某个固定
   release 以保证长期可复现？前者更新，后者更稳。
2. **缓存目录默认位置**：`~/.cache/nanoamp/ref/`（遵循 XDG，Linux 习惯）还是
   `04_results/.cache/`（跟项目走）？建议前者，可用 `NANOAMP_CACHE_DIR` 覆盖。
3. **`Consequence` 用英文枚举还是中英双列？** 建议英文枚举 + 文档中英对照。
4. **`protein_change` 是否需要严格 HGVS？** 本方案建议"HGVS 风格但非合规"。
5. **注释是否要在 UI（TUI / 桌面）里可视化？** §2D.2 已给出转录本多选界面草案，
   需与 `TUI_plan.1.md`、`UI_options.2.md` 合并排期（对应 A8）。

**C. 已知取舍（不是问题，但需要你知情）**

6. **不支持离线**：因取消本地文件，内网/气隙环境只能用路线一（§2B.4、R20）。
7. **结果可复现性依赖 Ensembl release**：manifest 会记录 release 与每个切片的 sha256；
   如日后需要"钉死版本"，用 `--ensembl-release` 即可，无需回到本地文件（§2A.5）。
8. **首次运行需要网络**：之后同一批样本命中缓存即不再联网（§2A.4）。

---

## 12. 与既有决策的一致性检查

| 既有决策 | 是否冲突 | 说明 |
|---|---|---|
| 一份参数契约（`shared/`） | 不冲突 | 注释开关与配置路径进 `default_params.json` |
| 数据与代码分离 | 不冲突 | 配置建议放 `configs/`，结果仍在 `04_results/` |
| 不新增重型依赖（报告 9/10） | **不冲突** | D1+D2 零新增依赖：翻译用 Biostrings，蛋白比对复用 `pa_pairwise_alignment()`，GTF 与 `.fai` 自己最小实现，不引入 rtracklayer / GenomicFeatures / Rsamtools 之外的重依赖 |
| 输出契约向后兼容 | 不冲突 | 新列追加在末尾；关闭注释时零变化 |
| 4 平台预置二进制 | 不冲突 | 注释是纯 R 计算 |
| 大文件不进 Git（报告 8/9 的 `01_data`、`03_dependence` 处理方式） | **更好** | 用户完全不必持有 4.5 GB 参考文件；缓存目录在仓库外且可直接删除 |
| 外部工具优先从 `03_dependence` 解析（报告 9） | 一致 | 联网优先用 `curl` 命令，可复用该解析机制；也可退回 R 自带 `url()` |
| "不新增重型依赖"（报告 9/10） | 一致 | 只用 `curl`（外部命令，已有机制）+ `jsonlite`（已是 Imports），**不动依赖清单** |
| 输出契约向后兼容（报告 8） | 一致 | `All` 采用追加行 + 追加列（§2D.3），不改变既有列名与顺序 |
| GUI 归姊妹仓库 | 不冲突 | 本方案是算法层；UI 暴露方式见待确认问题 10 |
| 合成数据为主要验收手段 | 一致 | F4 表明别无选择；A5 另加"与 GENCODE 官方 `protein.faa` 对拍"这一外部校验 |
| §7.2 建议"第一版先做 CDS 模式" | 一致 | A1 先做 CDS；但委托方点名 GTF，故 A5（基因组模式）仍保留在本方案范围内 |
| §7.2 把"基因组模式"列为"第二版再做" | **有意偏离，需确认** | 拿到 GENCODE v50（全基因组注释）后，**没有**"转录本模式"可用（F9：交付数据无基因组坐标），只能直接做基因组模式。这是本方案与 §7.2 原排期的唯一偏离，已在此显式记录 |
