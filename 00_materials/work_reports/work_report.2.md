# 工作报告 2：目录结构重构与方案 B 完善

> 日期：2026-09-20
> 关联：`work_report.1.md`、`programs_dev_plan_1.md`
> 本轮范围：多语言目录重构、DECIPHER 方案 B 完善、回归测试

---

## 1. 本轮目标

1. 调整 `02_code/` 与 `04_results/` 结构，为后续 Python 版本、统一 CLI、Windows GUI 开发留好位置；
2. 在 DECIPHER 成功安装后，用 DECIPHER 的正式 API 完善方案 B（从头聚类 + 簇共识）；
3. 保证方案 A/C 行为不变，并重新跑完整功能测试。

---

## 2. 目录结构重构

### 2.1 新结构

```text
02_code/
├── README.md                    # 多语言总览
├── shared/                      # 跨语言契约
│   ├── params/default_params.json
│   └── docs/output_schema.md
├── r/                           # R 实现（当前可用）
│   ├── R/
│   ├── scripts/
│   ├── tests/
│   ├── tools/prepare_test_data.R
│   ├── config/default_params.R
│   ├── README.md
│   └── nanoamp.Rproj
├── python/                      # Python 实现（占位）
│   ├── pyproject.toml
│   ├── src/nanoamp/__init__.py
│   └── tests/test_placeholder.py
├── cli/README.md                # 跨语言 CLI 契约
└── gui/README.md                # Windows GUI 规划
```

```text
04_results/
├── README.md
├── r/          # R 运行结果
├── python/     # Python 运行结果（预留）
├── cli/        # CLI 测试结果（预留）
└── gui/        # GUI 测试结果（预留）
```

### 2.2 旧路径 → 新路径

| 旧路径 | 新路径 |
|---|---|
| `02_code/R/` | `02_code/r/R/` |
| `02_code/scripts/` | `02_code/r/scripts/` |
| `02_code/tests/` | `02_code/r/tests/` |
| `02_code/config/` | `02_code/r/config/` |
| `02_code/scripts/prepare_test_data.R` | `02_code/r/tools/prepare_test_data.R` |
| `02_code/README.md` | `02_code/r/README.md`（新的 `02_code/README.md` 为多语言总览） |
| `nanoamp.Rproj`（项目根） | `02_code/r/nanoamp.Rproj` |
| `04_results/test_run_1/` | `04_results/r/test_run_1/` |
| `04_results/dev_*/`、`cli_smoke/`、`test_preview/` | `04_results/r/...` |

### 2.3 跨语言契约

新增 `02_code/shared/`，Python / GUI / R 必须共同遵守：

- `params/default_params.json`：统一参数名与默认值；
- `docs/output_schema.md`：`haplotypes.tsv`、`haplotypes.fasta`、`variants.tsv`、`qc.tsv`、`run_manifest.json` 的字段定义；
- `02_code/cli/README.md`：统一 CLI 命令、参数、输入表格式和退出码；
- `02_code/gui/README.md`：GUI 将调用 CLI 或核心库，不重复实现算法。

### 2.4 结果目录策略

- 运行结果按语言隔离：`04_results/r/`、`04_results/python/`、`04_results/cli/`、`04_results/gui/`；
- `04_results/` 下只保留 `README.md` 进入 Git，其余运行产物继续忽略；
- `.gitignore` 已从 `04_results/` 调整为 `04_results/*` + `!04_results/README.md`。

### 2.5 R 代码配套修改

| 文件 | 修改 |
|---|---|
| `run_analysis.R` | 打开 `02_code/r/nanoamp.Rproj`；脚本自动向上寻找项目根目录；输出默认到 `04_results/r/...` |
| `testthat.R` | 按新层级计算 `code_dir = 02_code/r` |
| `run_functional_tests.R` | 同上；默认输出 `04_results/r/test_run_1` |
| `test-core.R` | 项目根路径层级更新；新增 DECIPHER 路径断言 |
| `tools/prepare_test_data.R` | 项目根向上 3 层；软链接与 manifest 逻辑不变 |
| `scripts/nanoamp.R` | 路径逻辑不变（`scripts/` 与 `R/` 仍为兄弟目录）；方案 B 默认 `--consensus-method decipher` |

---

## 3. 方案 B 完善（DECIPHER 2.26.0）

### 3.1 实际可用的 DECIPHER API

安装后确认：

- `DistanceMatrix`：可用，计算序列距离；
- `Clusterize`：可用，直接返回聚类结果；
- `AlignSeqs`：可用，多序列比对；
- `ConsensusSequence`：可用，但其结果可能包含 IUPAC 模糊码和 `+`；
- `IdClusters`：**该版本不存在**，因此不能沿用原计划中的 API。

### 3.2 新流程

```text
比对到参考，统一方向并截取扩增子区段
  → 重建每条 read 的序列（保留全部差异）
  → DECIPHER::DistanceMatrix 计算距离矩阵
  → DECIPHER::Clusterize 按 identity_cutoff 聚类
  → 每个簇用 DECIPHER::AlignSeqs 做 MSA
  → 多数投票生成无 gap 共识（避免 IUPAC 模糊码和 +）
  → 大簇超过 max_msa_seqs 时保留 medoid 并系统抽样
  → pairwiseAlignment 描述簇共识相对参考的差异
```

### 3.3 默认参数变化

| 参数 | 旧默认 | 新默认 |
|---|---:|---:|
| `consensus_method` | `medoid` | `decipher` |
| `max_msa_seqs` | 20 | 100 |
| `identity_cutoff` | 0.99 | 0.99（不变） |

### 3.4 降级策略

- DECIPHER 不可用或聚类失败：降级为“变异模式贪心聚类”；
- `AlignSeqs` 失败：该簇降级为 medoid；
- 所有情况都在 `qc.tsv` 中记录：
  - `clustering_method`；
  - `consensus_method`；
  - `decipher_version`。

### 3.5 版本兼容

代码按能力检测 API，而不是写死版本：

1. 有 `Clusterize` → 使用 `DECIPHER::Clusterize`；
2. 只有 `IdClusters` → 使用 `DistanceMatrix + IdClusters`；
3. 两者都没有 → `DistanceMatrix + hclust + cutree`；
4. DECIPHER 完全不可用 → 变异模式贪心聚类。

---

## 4. 验证结果

### 4.1 单元测试

```bash
Rscript 02_code/r/tests/testthat.R
```

通过，包括：

- `cs` tag 解析；
- `apply_variants` / signature 往返；
- 方案 A/B/C 合成数据测试；
- 方案 B 在 DECIPHER 可用时使用 `DECIPHER::Clusterize`；
- `ln_test_data` manifest 软链接完整性。

### 4.2 环境检查

```bash
Rscript 02_code/r/scripts/nanoamp.R doctor
```

DECIPHER 显示为 `TRUE`，版本 2.26.0。

### 4.3 完整功能测试

```bash
Rscript 02_code/r/tests/run_functional_tests.R \
  --outdir 04_results/r/test_run_1 --modes A,B,C --threads 4
```

结果：168 次运行（每模式 56 次），**0 次失败**。

| 模式 | 运行数 | 成功 | top1 平均比例 | 公司变异平均重合率 | 平均耗时 |
|---|---:|---:|---:|---:|---:|
| A | 56 | 56 | 0.6748 | 0.9807 | 0.76 s |
| B | 56 | 56 | 0.7393 | 0.5497 | 5.56 s |
| C | 56 | 56 | 0.1231 | 0 | 0.17 s |

方案 B 的 56 次运行全部使用：

```text
clustering_method = DECIPHER::Clusterize
consensus_method  = decipher
decipher_version  = 2.26.0
```

### 4.4 方案 B 改进对比

| 指标 | 之前的后备聚类 | DECIPHER 聚类 |
|---|---:|---:|
| 公司变异平均重合率 | 0.3771 | **0.5497** |
| top1 平均比例 | 0.8663 | 0.7393 |
| 平均耗时 | 1.55 s | 5.56 s |

在 23 个“self 参考 + 公司变异表”的运行上：

- 公司变异 167 个；
- DECIPHER 方案 B 命中 113 个（67.7%）；
- 7 / 23 个样本达到 100%；
- 方案 A 仍为 163 / 167（97.6%），22 / 23 个样本 100%。

结论：

- DECIPHER 显著改善了方案 B 的聚类结构和共识质量；
- 但方案 B 仍然无法分离差异小于测序错误率的单倍型；
- **定量和最终结论仍应使用方案 A**，方案 B 作为无参考 / 探索性分析。

### 4.5 E4-3 案例

方案 B（DECIPHER）结果：

| 排名 | 簇 | reads | 比例 | 变异 |
|---:|---:|---:|---:|---|
| 1 | 1 | 128 | 30.05% | `220delG` |
| 2 | 4 | 118 | 27.70% | `135C>T;220delG` |
| 3 | 10 | 107 | 25.12% | 参考序列 |
| 4 | 7 | 33 | 7.75% | `135C>T` |
| 5 | 16 | 3 | 0.70% | `135C>T;190T>C;220delG` |

与方案 A 的组成（218delG 33.3%、参考 31.5%、218delG+135C>T 26.8%）基本一致。缺失位置标注为 220 而不是 218，是重复区 indel 左对齐差异，序列本身一致。

---

## 5. 当前已知限制

1. **方案 B 的分辨率受测序错误率限制**
   - 两个真实单倍型若只差 1–2 个碱基，而单条 read 有 4–6 个测序错误，de novo 聚类无法稳定分开；
   - 这是方法本身的限制，不是 DECIPHER 的问题。

2. **方案 B 的 indel 位置标注可能与公司不同**
   - 重复区缺失可能被标注在 220 而不是 218；
   - 需要后续加入标准左对齐和区段归一化。

3. **大簇 MSA 仍有成本**
   - 当前默认 `max_msa_seqs=100`，超过则系统抽样；
   - 对十万级 reads 的单簇，仍需专门的降采样或增量共识策略。

4. **方案 A 的多单倍型参考问题仍存在**
   - 低比对率样本（`clone_11`、`G2-1-9`、`293T-G2`）需要逐簇参考或统一参考策略。

5. **Python / GUI 仍是占位**
   - 目录、参数契约和输出 schema 已就位，但算法尚未实现。

---

## 6. 下一步建议

1. 在 `02_code/python/` 下实现方案 A 的 Python 版本，并用 `02_code/shared/` 契约与 R 版本对齐；
2. 增加 R/Python 结果一致性测试；
3. 为方案 B 增加标准 indel 左对齐；
4. 对低比对率样本实现“逐簇参考”模式；
5. 开始 Windows GUI 技术验证（PySide6 + PyInstaller + 打包 minimap2）；
6. 继续推进 GTF/CDS 功能注释。

---

## 7. 复现命令

```bash
# 环境检查（应显示 DECIPHER TRUE）
Rscript 02_code/r/scripts/nanoamp.R doctor

# 重建测试数据软链接
Rscript 02_code/r/tools/prepare_test_data.R

# 单元测试
Rscript 02_code/r/tests/testthat.R

# 方案 A 单样本
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

# 完整功能测试
Rscript 02_code/r/tests/run_functional_tests.R \
  --outdir 04_results/r/test_run_1 --modes A,B,C --threads 4
```

RStudio：打开 `02_code/r/nanoamp.Rproj`，运行 `02_code/r/scripts/run_analysis.R`。

---

## 8. Git 提交

| 提交 | 说明 |
|---|---|
| `ce69fd6` | docs: add work report 1 for R core algorithms |
| `a27164f` | refactor: reorganize project layout and complete DECIPHER mode B |

本轮测试产物位于 `04_results/r/test_run_1/`，按约定不进入 Git。
