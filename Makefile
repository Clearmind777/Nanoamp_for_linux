R_PKG := 02_code

.PHONY: help install test check cli deps test-data functional-test clean-builds

help:
	@echo "nanoamp project targets:"
	@echo "  make install      Install the R package (R CMD INSTALL $(R_PKG))"
	@echo "  make test         Run testthat tests"
	@echo "  make check        Build and R CMD check into 05_builds/r"
	@echo "  make cli          Run 'nanoamp doctor' from the repository CLI"
	@echo "  make deps         Fetch bundled external tools where possible"
	@echo "  make test-data    Regenerate 01_data/manifest.tsv from 01_data/test_data"
	@echo "  make functional-test Run all datasets x modes (needs R deps + minimap2)"
	@echo "  make clean-builds Remove 05_builds/r contents"

install:
	R CMD INSTALL $(R_PKG)

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

test-data:
	Rscript 02_code/scripts/prepare_test_data.R

functional-test:
	Rscript 02_code/scripts/run_functional_tests.R \
	  --outdir 04_results/r/test_run_local --modes A,B,C --threads 4

clean-builds:
	rm -rf 05_builds/r/*
