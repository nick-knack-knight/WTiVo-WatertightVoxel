# Ubuntu 24.04 build (Python 3.12, PyTorch 2.8.0, CUDA 12.8, RTX A6000)

## Target baseline

| Item | Value |
|---|---|
| OS | Ubuntu 24.04 LTS x86_64 |
| Python | 3.12 (Ubuntu 24.04 system Python) |
| PyTorch | 2.8.0+cu128 (official PyTorch cu128 wheel index) |
| CUDA Toolkit | 12.8 with `nvcc` (`/usr/local/cuda-12.8`) |
| GPU | NVIDIA RTX A6000 (Ampere, compute capability 8.6, 48 GB) |
| Compiler | system GCC 13 (supported by CUDA 12.8) |

The NVIDIA driver (>= 570 for CUDA 12.8) and the CUDA Toolkit 12.8 are prerequisites
and are never installed by WTiVo. Check with `nvidia-smi` and `/usr/local/cuda-12.8/bin/nvcc --version`.

## Setup

```bash
git clone https://github.com/nick-knack-knight/WTiVo-WatertightVoxel.git
cd WTiVo-WatertightVoxel
scripts/setup_ubuntu.sh
```

The script (re-runnable):

1. installs apt packages (Python 3.12 venv/dev, build tools, Eigen, oneTBB, Boost, GMP/MPFR);
2. creates `.venv`, installs `torch==2.8.0` (cu128) and the pinned requirements;
3. downloads header-only CGAL 6.0.1 and builds OpenVDB 11.0.0 into `.deps/`;
4. builds `wtivo_core` and `wtivo_vdb` with CMake/Ninja into `build/`;
5. builds the CUDA extension `wtivo_gpupr` for `sm_86` (detected from the GPU, defaulting to 8.6 when no GPU is visible, e.g. in a build container);
6. writes `.wtivo-env.sh` (`LD_LIBRARY_PATH`, CUDA home) and runs `scripts/verify_install.py`.

Options: `--skip-apt`, `--cuda-arch 8.6` (or `WTIVO_CUDA_ARCH`), `WTIVO_CUDA_HOME`, `WTIVO_JOBS`.

## Run

```bash
./run-wtivo.sh --input model.glb --output model_watertight.glb --input-res 1536 --final-res 1536 --lambda_fill 10
```

## Building once, copying elsewhere

`setup_ubuntu.sh` bundles `libopenvdb.so*` into `build/` and writes `build/BUILD_INFO.json`.
To reuse the compiled extensions on another machine (or in the ComfyUI node's `backend/build`):

```bash
scripts/package_build.sh                      # -> wtivo-build-linux.tar.gz
tar -xzf wtivo-build-linux.tar.gz -C /path/to/other/build   # or any directory
export WTIVO_BUILD_DIR=/path/to/other/build   # optional: build dir outside the checkout
.venv/bin/python scripts/verify_install.py --e2e
```

The target must match `BUILD_INFO.json` (Python 3.12, same torch 2.8.x, same GPU architecture, e.g. sm_86) and have
the apt runtime libs (`libtbb12 libgmp10 libmpfr6 libboost-iostreams`). `wtivo.py` prints a warning when the
manifest does not match the running Python/torch.

## Notes

* Windows-specific code paths (DLL directories, CRT heap compaction, Win32 memory
  counters) are guarded; Linux uses `malloc_trim` and `/proc` for the memory
  snapshots.
* The 1536/12M benchmark was measured on Windows/RTX 5050; the Ubuntu/A6000 build
  has not been benchmarked by the original author.
