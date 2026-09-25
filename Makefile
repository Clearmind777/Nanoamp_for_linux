R_PKG := 02_code

.PHONY: help install deps-r test check cli deps deps-all test-data functional-test clean-builds release release-publish release-check

help:
	@echo "nanoamp project targets:"
	@echo "  make install      Install the R package (R CMD INSTALL $(R_PKG))"
	@echo "  make deps-r       Install the R dependencies (pak first, then CRAN/Bioc)"
	@echo "  make test         Run testthat tests"
	@echo "  make check        Build and R CMD check into 05_builds/r"
	@echo "  make cli          Run 'nanoamp doctor' from the repository CLI"
	@echo "  make deps         Refresh the bundled minimap2 for the host platform"
	@echo "  make test-data    Regenerate 01_data/manifest.tsv from 01_data/test_data"
	@echo "  make functional-test Run all datasets x modes (needs R deps + minimap2)"
	@echo "  make clean-builds Remove 05_builds/r contents"
	@echo "  make release      Build all release/ artifacts from the current tag/commit"
	@echo "  make release-check Verify release/ checksums and metadata (no publishing)"
	@echo "  make release-publish Publish release/ to GitHub (needs gh auth or GH_TOKEN)"

install:
	R CMD INSTALL $(R_PKG)

# minimap2 is already bundled for the four supported platforms; this only
# installs the R packages, which are the part that cannot be pre-bundled.
deps-r:
	Rscript 02_code/scripts/install_r_deps.R

# testthat loads the source package with pkgload, which (unlike devtools) is a
# declared dependency and is what the repository CLI launcher uses as well.
test:
	Rscript -e 'pkgload::load_all("$(R_PKG)", quiet = TRUE); testthat::test_dir(file.path("$(R_PKG)", "tests", "testthat"), reporter = "summary", stop_on_failure = TRUE)'

check:
	mkdir -p 05_builds/r
	R CMD build $(R_PKG) --no-build-vignettes
	mv nanoamp_*.tar.gz 05_builds/r/
	cd 05_builds/r && R CMD check --no-manual --no-build-vignettes nanoamp_*.tar.gz

cli:
	sh 02_code/cli/nanoamp doctor

deps:
	bash 03_dependence/fetch_dependencies.sh

deps-all:
	bash 03_dependence/fetch_dependencies.sh --all

test-data:
	Rscript 02_code/scripts/prepare_test_data.R

functional-test:
	Rscript 02_code/scripts/run_functional_tests.R \
	  --outdir 04_results/r/test_run_local --modes A,B,C --threads 4

clean-builds:
	rm -rf 05_builds/r/*

# --- 发布 -------------------------------------------------------------------
# 从当前 tag（没有 tag 则用 HEAD）构建 release/ 下的全部产物，并重写 manifest.tsv。
release:
	bash 02_code/scripts/mk-release.sh --ref "$$(git describe --tags --exact-match 2>/dev/null || echo HEAD)"

# 只做校验：校验和 + 元数据 + 发布前置条件，不发布。
release-check:
	DRY_RUN=1 bash release/publish_github_release.sh

# 需要 gh auth login 或 GH_TOKEN；脚本幂等，Release 已存在时覆盖同名附件。
release-publish:
	bash release/publish_github_release.sh
