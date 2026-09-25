# 工作报告 12：注释功能的三项优化

> 日期：2026-09-25
> 关联：`work_report.11.md`（功能注释首版）、`00_materials/optional_function.md`
> 本轮范围：落实报告 11 末尾列出的"下一轮建议"——
> ① 负链坐标映射；② `--annotation-proteins` / `--annotation-detail`；③ Mode B 注释端到端验证。

---

## 1. 负链扩增子支持

### 1.1 坐标映射

扩增子参考处于**reads 自身的方向**，因此当它匹配到基因组**负链**时，其第 1 位对应
**最高**的基因组坐标：

| 变异类型 | 换算 |
|---|---|
| 替换 / 缺失（锚定在起始碱基） | `genome = end - pos + 1` |
| 插入（锚定在插入点**之后**的碱基） | `genome = end - pos + 2` |

等位基因一律反向互补，使所有操作都能作用在正链序列上。

### 1.2 定位层

`.annotation_confirm_hit()` 增加负链分支：对窗口做反向互补后再找锚点，命中则报 `strand = "-"`，
并由锚点在反向互补序列中的位置反推正链起点。

### 1.3 镜像测试（本轮新增，核心保障）

`test-annotate.R` 新增：同一生物学变异分别用正链与负链表述，必须得到**相同**的
`genome_pos`、`consequence` 与 `protein_change`。另有针对性测试固定插入/缺失的 ±1 锚点差异。

实测（合成 300 bp 片段 + 真实密码子结构）：

```text
正链: genome_pos 78 | stop_gained p.Ser10Thr
负链: genome_pos 78 | stop_gained p.Ser10Thr
镜像一致 (protein_change): TRUE
镜像一致 (consequence)   : TRUE
```

过程中发现我第一次的测试输入把**基因组坐标当成扩增子坐标**，导致正链一侧算错；
镜像测试正是用来暴露这类"单侧看起来正常"的错误。

## 2. `--annotation-proteins` 与 `--annotation-detail`

| 开关 | 产出 |
|---|---|
| `--annotation-proteins` | `annotation.tsv` 追加 `ref_protein` / `alt_protein` 两列（默认不输出，避免表过宽） |
| `--annotation-detail` | 另写 `variants_annotation.tsv`：每个变异一行 |

`variants_annotation.tsv` 列：

```text
haplotype_id transcript_id type genome_pos cds_pos ref alt
codon_ref codon_alt aa_ref aa_alt consequence_en consequence_zh
```

这是**单变异视角**：每个变异单独作用一次再读密码子/氨基酸。文档中明确写出
"多变异组合的最终后果以 `annotation.tsv` 为准，两者可能不同"——避免用户把两者混为一谈。

离线实测（cds 路线，14 行明细）：

```text
H2 ins 114 frameshift
H2 ins 120 inframe_insertion
H2 snv 117 GAT->GAC  D->D  synonymous
H2 snv 122 CTA->CGA  L->R  missense
```

## 3. Mode B 注释端到端验证

报告 11 遗留项。实测（WT 样本，cds 路线，离线）：

```text
Mode B 完成 | 簇数: 2
annotation 可用: TRUE | 行数: 2
  簇1 55 reads  synonymous 同义 p.(=)
  簇2  1 reads  synonymous 同义 p.(=)
annotation.tsv 存在: TRUE | qc.tsv 含注释指标: TRUE
```

说明簇共识序列（`consensus` 列）已被正确取用并完成注释；因该样本无变异，
`variants_annotation.tsv` 不生成（无变异可列），符合预期。

## 4. 顺带修掉的问题

| 问题 | 说明 |
|---|---|
| 单元测试会**意外联网** | 一个离线测试调用 V1 校验，而 V1 需要向 Ensembl 取官方蛋白，导致每个测试文件跑 60 秒。给序列获取与 V1 增加 `retries` 参数，测试用 `retries = 1` 并把 base URL 指向不可达地址，使其**完全不触网**（测试套件回到 2 秒） |
| 过时测试 | "负链应被拒绝"的测试在实现负链后失效，替换为坐标换算的固定测试 |

## 5. 验证

| 检查 | 结果 |
|---|---|
| `make test`（注释测试增至 21 组） | 全部通过，且不触网 |
| `R CMD check --no-manual` | **Status: OK** |
| 功能测试（168 runs，未启用注释） | **168/168 ok**；A=0.6750/0.9807、C=0.1231 与基线一致 |
| 负链镜像一致性 | TRUE（consequence 与 protein_change 均一致） |
| `--annotation-detail` | 14 行明细，密码子/氨基酸/后果均正确 |
| `--annotation-proteins` | 两列蛋白序列正确输出 |
| Mode B 注释 | 端到端可用 |

## 6. 仍未完成

- 负链在**真实数据**上的端到端验证：`01_data` 的靶点都定位在正链，因此负链逻辑目前只有
  合成镜像测试与算术测试覆盖。若要更强的证据，需要一份真实的负链扩增子样本。
- `overlap/id?feature=exon` 返回的是整个位点的外显子，因此 UTR 判定按"是否落在任意外显子"
  处理；精确到转录本需要额外结构来源。
- 注释结果接入 TUI（`TUI_plan.1.md` 的转录本多选界面）仍未开始。
