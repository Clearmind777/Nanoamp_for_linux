# ---------------------------------------------------------------------------
# 加载所有 R 模块
# 用法：
#   在 RStudio 中：code_dir <- "."; source("R/load_all.R")
#   在脚本中：code_dir <- <02_code 路径>; source(file.path(code_dir, "R/load_all.R"))
# ---------------------------------------------------------------------------

if (!exists("code_dir", inherits = TRUE)) {
  code_dir <- getwd()
}

.nanoamp_modules <- c(
  "utils.R",
  "io.R",
  "align.R",
  "variants.R",
  "correct.R",
  "cluster.R",
  "exact.R",
  "haplotypes.R"
)

for (.f in .nanoamp_modules) {
  .path <- file.path(code_dir, "R", .f)
  if (!file.exists(.path)) stop(sprintf("缺少模块文件: %s", .path), call. = FALSE)
  source(.path, local = FALSE, encoding = "UTF-8")
}

rm(.f, .path, .nanoamp_modules)
