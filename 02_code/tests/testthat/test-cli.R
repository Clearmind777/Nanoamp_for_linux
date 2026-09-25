# ---------------------------------------------------------------------------
# The CLI must not accept abbreviated long flags.
#
# optparse (via getopt) resolves unambiguous prefixes, so `--annotate` binds to
# `--annotate-config` and `--ref` to `--ref-label`. The old RELEASE_NOTES
# examples used `--annotate` / `--annotation-route` / `--ref`, and silently
# mis-binding them produced messages like "Annotation config not found: genome".
# ---------------------------------------------------------------------------

test_that("abbreviated long flags are rejected with the real flag suggested", {
  opts <- cli_call_options()

  expect_error(cli_check_flags(c("--reads", "x", "--annotate", "genome"), opts),
               "Unknown option '--annotate'")
  expect_error(cli_check_flags(c("--reads", "x", "--annotate", "genome"), opts),
               "--annotate-config")
  expect_error(cli_check_flags(c("--ref", "a.fa"), opts), "Unknown option '--ref'")
  expect_error(cli_check_flags(c("--ref", "a.fa"), opts), "--reference")
  expect_error(cli_check_flags(c("--anno", "cfg.json"), opts), "Abbreviations are not accepted")
})

test_that("exact flags, including --help and the values of other flags, pass", {
  opts <- cli_call_options()

  expect_silent(cli_check_flags(
    c("--reads", "r.fastq", "--reference", "ref.fa", "--outdir", "out",
      "--mode", "A", "--annotate-config", "cfg.json", "--cache-dir", "/tmp/c",
      "--top-n", "20"), opts))
  expect_silent(cli_check_flags("--help", opts))
  # a value that happens to look like a flag must not be inspected as one
  expect_silent(cli_check_flags(c("--ref-label", "--weird-label"), opts))
})
