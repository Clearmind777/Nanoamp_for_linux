# windows-x86_64

There are no official Windows binaries for minimap2 or samtools.

Recommended options:

1. **Use the R-native backend**:

```r
run_haplotype_analysis(..., aligner = "r")
```

This uses Biostrings pairwise alignment and needs no external tool.

2. **Use WSL2**: install Ubuntu and run the Linux version of nanoamp inside
   WSL, using `03_dependence/linux-x86_64/`.

3. If you have third-party Windows binaries, place them here:

```text
03_dependence/windows-x86_64/bin/minimap2.exe
03_dependence/windows-x86_64/bin/samtools.exe
```

nanoamp will resolve them automatically.
