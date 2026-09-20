# macos-arm64

No binary is bundled. Use conda:

```bash
conda create -p 03_dependence/macos-arm64/conda \
  -c conda-forge -c bioconda minimap2 samtools
cp 03_dependence/macos-arm64/conda/bin/minimap2 03_dependence/macos-arm64/bin/
cp 03_dependence/macos-arm64/conda/bin/samtools 03_dependence/macos-arm64/bin/
```

Alternatively, run nanoamp with `aligner = "r"`.
