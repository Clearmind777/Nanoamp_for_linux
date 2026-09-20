# 02_code：源代码目录

本目录按“共享契约 + 各语言独立实现 + 各交付形态”组织。R 版本已经完成，
Python、CLI 和 GUI 预留了标准位置。

```text
02_code/
├── shared/                 # 跨语言参数与输出 schema
│   ├── params/default_params.json
│   └── docs/output_schema.md
├── r/                      # R 包（当前可用）
│   ├── R/
│   ├── inst/scripts/
│   ├── tests/
│   ├── DESCRIPTION
│   └── README.md / README-CN.md
├── python/                 # Python 实现（占位）
├── cli/                    # CLI 契约与包装
└── gui/                    # Windows GUI（规划中）
```

## 设计原则

1. **一套算法，多种外壳**：GUI 和 Web 调用 CLI 或核心库，不重复实现分析逻辑；
2. **共享契约**：参数名、默认值和输出列在 `shared/` 统一定义，各语言实现共同遵守；
3. **数据与代码分离**：测试数据在 `01_data/`，运行结果在 `04_results/<语言>/`；
4. **各语言自包含**：R 包位于 `02_code/r`，未来 Python 包位于 `02_code/python`。

## R 包快速开始

```bash
# 安装 R 包
R CMD INSTALL 02_code/r

# 环境检查
nanoamp doctor

# 单样本分析
nanoamp call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --top-n 20 \
  --outdir 04_results/r/demo/E4-3
```

R 控制台：

```r
library(nanoamp)
res <- run_haplotype_analysis(
  reads     = "01_data/ln_test_data/TSM20260826/E4-3/reads.fastq",
  reference = "01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa",
  outdir    = "04_results/r/demo/E4-3",
  mode      = "A"
)
res$haplotypes
```

完整教程见 `02_code/r/README.md`（英文）和 `02_code/r/README-CN.md`（中文）。

## 当前状态

| 组件 | 状态 |
|---|---|
| R 包 | 已实现，并通过 `R CMD check`（`Status: OK`） |
| 基于 R 的 CLI | 已实现（`nanoamp call` / `batch` / `doctor`） |
| Python 包 | 占位 |
| Windows GUI | 规划中 |

## 共享契约

- `shared/params/default_params.json`：参数名与默认值；
- `shared/docs/output_schema.md`：输出文件与字段定义；
- `cli/README.md`：CLI 命令契约。
