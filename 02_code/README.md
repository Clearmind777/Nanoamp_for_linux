# 02_code 代码目录

本目录按“共享契约 + 各语言独立实现 + 各交付形态独立子目录”组织，R 版本已实现，Python / CLI / GUI 预留了标准位置。

```text
02_code/
├── shared/                 # 跨语言共享的参数、输出 schema、接口契约
│   ├── params/default_params.json
│   └── docs/output_schema.md
├── r/                      # R 实现（当前可用）
│   ├── R/                  # 核心算法模块
│   ├── scripts/            # RStudio / Rscript 入口
│   ├── tests/              # testthat 单元测试 + 功能测试
│   ├── tools/              # 数据准备脚本
│   ├── config/
│   └── nanoamp.Rproj
├── python/                 # Python 实现（待开发）
│   ├── src/nanoamp/
│   ├── tests/
│   └── pyproject.toml
├── cli/                    # 跨语言命令行契约与发布入口（待开发）
└── gui/                    # Windows GUI（待开发）
```

## 设计原则

1. **算法只实现一次，各形态薄封装**：R 和 Python 可以各自实现，但参数名、输入输出和结果 schema 必须遵循 `shared/` 下的契约，保证同一输入在两种实现下结果可比。
2. **数据与代码分离**：测试数据在 `01_data/`，运行结果在 `04_results/<language>/...`。
3. **每个语言目录自包含**：R 项目打开 `02_code/r/nanoamp.Rproj`；Python 项目后续在 `02_code/python/` 下管理虚拟环境和依赖。
4. **CLI 是统一入口**：GUI 和 Web 最终调用 CLI 或核心库，而不是各自实现一套分析逻辑。

## R 版本快速开始

```bash
# 环境检查
Rscript 02_code/r/scripts/nanoamp.R doctor

# 生成测试数据软链接
Rscript 02_code/r/tools/prepare_test_data.R

# 单样本分析
Rscript 02_code/r/scripts/nanoamp.R call \
  --reads 01_data/ln_test_data/TSM20260826/E4-3/reads.fastq \
  --reference 01_data/ln_test_data/TSM20260826/E4-3/reference.self.fa \
  --mode A --top-n 20 \
  --outdir 04_results/r/demo/E4-3

# 单元测试
Rscript 02_code/r/tests/testthat.R

# 功能测试
Rscript 02_code/r/tests/run_functional_tests.R \
  --outdir 04_results/r/test_run_1 --modes A,B,C
```

RStudio：打开 `02_code/r/nanoamp.Rproj`，编辑并运行 `02_code/r/scripts/run_analysis.R`。

详细说明见 `02_code/r/README.md`；跨语言参数与输出定义见 `02_code/shared/`。
