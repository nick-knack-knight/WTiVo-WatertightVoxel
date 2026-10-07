# Changelog

## Unreleased

- Forward-ported the v1.1 runner features to Linux for the ComfyUI node: `--proxy_points`, `--proxy_eps_scale`, native-array `.npy` bridge (`--input-vertices-npy` / `--input-faces-npy` / `--output-vertices-npy` / `--output-faces-npy`), input validation, and the secondary Trimesh closed/single-body audit in the `[FINAL]` line.
- Relocatable builds: `libopenvdb.so*` is bundled into `build/` (`$ORIGIN` rpath), `build/BUILD_INFO.json` records the Python/torch/arch ABI, `scripts/package_build.sh` creates a tarball, and `WTIVO_BUILD_DIR` points `wtivo.py` / `verify_install.py` at externally supplied extensions.
- `scripts/verify_install.py --e2e` runs the `.npy` bridge end to end on a GPU.
- Ubuntu 24.04 / Python 3.12 / PyTorch 2.8.0+cu128 / RTX A6000 (sm_86) build: `scripts/setup_ubuntu.sh`, `run-wtivo.sh`, cross-platform CMake and `build_gpupr.py`, Linux memory/heap handling in `wtivo.py`.

## 1.0.0 — 2026-08-25

First public source release of **WTiVo: WatertightVoxel Optimizer**.

- fixed 12M direct FaithC/QEF point-budget proxy;
- sparse OpenVDB thick and signed final fields;
- CGAL Parallel-tag Delaunay tetrahedra with direct neighbor export;
- CelloCut-compatible fill-aware graph objective;
- multi-discharge CUDA Push-Relabel solver;
- chunked GPU topology handling;
- manifold FaithC-style contour splitting and local watertight finalizer;
- exact final edge-degree watertight audit;
- Windows source-first setup with per-GPU CUDA architecture detection;
- complete attribution and GPL/Apache dependency license map.
