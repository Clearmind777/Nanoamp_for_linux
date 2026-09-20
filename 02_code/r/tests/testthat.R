#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(testthat))

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[1]) else "02_code/r/tests/testthat.R"
code_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
project_root <- normalizePath(file.path(code_dir, "..", ".."), mustWork = TRUE)

source(file.path(code_dir, "R", "load_all.R"))
testthat::test_dir(file.path(code_dir, "tests", "testthat"), reporter = "summary")
