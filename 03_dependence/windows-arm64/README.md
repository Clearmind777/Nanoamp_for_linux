# windows-arm64

There are no official Windows ARM64 binaries for minimap2 or samtools.

Recommended options:

1. use `aligner = "r"` (R-native alignment backend);
2. run the x86_64 Windows build under emulation, if available;
3. use WSL2 with the Linux ARM64 or x86_64 build.
