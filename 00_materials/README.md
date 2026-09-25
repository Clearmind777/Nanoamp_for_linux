# 00_materials

Planning documents and work reports for the nanoamp project.

```text
00_materials/
|-- programs_dev_info.md       # original brief and requested deliverables
|-- programs_dev_plan_1.md     # development plan (v1)
`-- work_reports/
    |-- work_report.1.md       # R core algorithms A/B/C
    |-- work_report.2.md       # directory refactor and DECIPHER mode B
    |-- work_report.3.md       # R package, tutorial and CLI
    |-- work_report.4.md       # R-only route, dependency guide and GUI v1
    |-- work_report.5.md       # bundled dependencies and cross-platform compatibility
    |-- work_report.6.md       # GitHub remote, Windows minimap2 build, local R regression
    |-- work_report.7.md       # Linux repo reduced to the CLI-only distribution
    |-- work_report.8.md       # ln_test_data removed, 02_code flattened, macOS arm64 verified
    |-- work_report.9.md       # minimap2 bundled for 4 platforms, samtools dropped, pak-first R deps
    |-- work_report.10.md      # linux cross-fetch fixed, ShortRead replaced by a base-R FASTQ reader
    |-- work_report.11.md      # functional annotation: online Ensembl reference, bilingual consequences
    `-- work_report.12.md      # annotation follow-up: minus strand, variant detail, Mode B verified
```

Start with `programs_dev_info.md` for the original request and
`programs_dev_plan_1.md` for the overall design.

The work reports are a historical log of how the project was developed; they are
kept verbatim and are not rewritten when the tree changes. Reports 5 and 6 in
particular describe cross-platform work, including the Windows material that now
lives only in the sister repository
`a_09_18_26_mapping_programs_dev_for_win`. Report 7 records the removal of the
offline runtime and of the GUI, so those parts of reports 4-6 are historical and
no longer describe the current tree. Report 8 records the removal of the
`ln_test_data` symlink layer, the flattening of `02_code/` and the verification
on macOS arm64; it lists the paths that changed, so reports 1-7 may still name
paths (`02_code/r/...`, `01_data/ln_test_data/...`) that no longer exist. Report 9
records the switch from a single Linux x86_64 bundled binary to a bundled
`minimap2` for all four supported platforms, and the removal of the bundled
`samtools`. Report 10 fixes cross-fetching linux-64 from macOS and replaces the
`ShortRead` FASTQ reader with a base-R parser, which is what finally makes the
default workflow independent of `pwalign`.
