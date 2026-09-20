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
    `-- work_report.7.md       # Linux repo reduced to the CLI-only distribution
```

Start with `programs_dev_info.md` for the original request and
`programs_dev_plan_1.md` for the overall design.

The work reports are a historical log of how the project was developed; they are
kept verbatim and are not rewritten when the tree changes. Reports 5 and 6 in
particular describe cross-platform work, including the Windows material that now
lives only in the sister repository
`a_09_18_26_mapping_programs_dev_for_win`. Report 7 records the removal of the
offline runtime and of the GUI, so those parts of reports 4-6 are historical and
no longer describe the current tree.
