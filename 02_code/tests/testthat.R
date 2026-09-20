#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(testthat))

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[1]) else "02_code/tests/testthat.R"
project_root <- normalizePath(file.path(dirname(script_path), "..", ".."), mustWork = TRUE)
code_dir <- file.path(project_root, "02_code")

source(file.path(code_dir, "R", "load_all.R"))
testthat::test_dir(file.path(code_dir, "tests", "testthat"), reporter = "summary")
