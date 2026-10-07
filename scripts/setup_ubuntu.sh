#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# WTiVo setup for Ubuntu 24.04 LTS x86_64 + Python 3.12 + PyTorch 2.8.0 (CUDA 12.8).
# Primary target GPU: NVIDIA RTX A6000 (Ampere, sm_86).
#
# Usage:  scripts/setup_ubuntu.sh [--skip-apt] [--cuda-arch 8.6]
# Env:    WTIVO_CUDA_HOME  CUDA Toolkit 12.8 root (default: /usr/local/cuda-12.8)
#         WTIVO_CUDA_ARCH  override compute capability (default: 8.6, or detected)
#         WTIVO_JOBS       parallel build jobs (default: nproc)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OPENVDB_VERSION="11.0.0"
CGAL_VERSION="6.0.1"
SKIP_APT=0
ARCH="${WTIVO_CUDA_ARCH:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-apt) SKIP_APT=1 ;;
    --cuda-arch) ARCH="$2"; shift ;;
    *) echo "[ERROR] unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

info() { echo "[WTiVo setup] $*"; }
fail() { echo "[WTiVo setup ERROR] $*" >&2; exit 1; }

[[ "$(uname -m)" == "x86_64" ]] || fail "x86_64 required"
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] || \
    info "WARNING: targeted at Ubuntu 24.04; found ${PRETTY_NAME:-unknown}"
fi
JOBS="${WTIVO_JOBS:-$(nproc)}"

# ---- system packages -------------------------------------------------------
if [[ $SKIP_APT -eq 0 ]]; then
  SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"
  info "Installing system packages (apt)..."
  $SUDO apt-get update
  $SUDO apt-get install -y ca-certificates curl wget git xz-utils
  $SUDO apt-get install -y python3.12 python3.12-venv python3.12-dev \
    build-essential pkg-config \
    libeigen3-dev libtbb-dev libboost-iostreams-dev libboost-system-dev \
    libboost-dev libgmp-dev libmpfr-dev zlib1g-dev
fi
command -v python3.12 >/dev/null 2>&1 || fail "python3.12 not found"

# ---- CUDA toolkit ----------------------------------------------------------
CUDA_HOME_DIR="${WTIVO_CUDA_HOME:-${CUDA_HOME:-}}"
if [[ -z "$CUDA_HOME_DIR" ]]; then
  for c in /usr/local/cuda-12.8 /usr/local/cuda; do
    [[ -x "$c/bin/nvcc" ]] && { CUDA_HOME_DIR="$c"; break; }
  done
fi
[[ -n "$CUDA_HOME_DIR" && -x "$CUDA_HOME_DIR/bin/nvcc" ]] || \
  fail "CUDA Toolkit 12.8 (nvcc) not found. Install it from https://developer.nvidia.com/cuda-12-8-0-download-archive (Linux > x86_64 > Ubuntu > 24.04) or set WTIVO_CUDA_HOME."
NVCC_VER="$("$CUDA_HOME_DIR/bin/nvcc" --version | sed -n 's/.*release \([0-9.]*\),.*/\1/p')"
info "CUDA toolkit: $CUDA_HOME_DIR (nvcc $NVCC_VER)"
[[ "$NVCC_VER" == 12.8* ]] || info "WARNING: nvcc $NVCC_VER != 12.8; PyTorch cu128 builds expect 12.8 (CUDA 12.x minor mismatch is tolerated by torch)."
export PATH="$CUDA_HOME_DIR/bin:$PATH"

# ---- Python venv + PyTorch -------------------------------------------------
if [[ ! -x .venv/bin/python ]]; then
  info "Creating .venv (Python 3.12)..."
  python3.12 -m venv .venv
fi
PY="$ROOT/.venv/bin/python"
"$PY" -c 'import sys; assert sys.version_info[:2]==(3,12), sys.version' || fail ".venv is not Python 3.12; delete .venv and rerun"
"$PY" -m pip install --upgrade pip setuptools wheel
"$PY" -m pip install --index-url https://download.pytorch.org/whl/cu128 torch==2.8.0
"$PY" -m pip install -r requirements-runtime.txt -r requirements-build.txt

if [[ -z "$ARCH" ]]; then
  ARCH="$("$PY" -c 'import torch;c=torch.cuda.get_device_capability(0) if torch.cuda.is_available() else None;print(f"{c[0]}.{c[1]}" if c else "8.6")')"
fi
info "Target CUDA arch: sm_${ARCH/./} (RTX A6000 = 8.6)"

mkdir -p .deps .build build
CMAKE="$ROOT/.venv/bin/cmake"; NINJA="$ROOT/.venv/bin/ninja"

# ---- CGAL (header-only) ----------------------------------------------------
CGAL_DIR="$ROOT/.deps/CGAL-$CGAL_VERSION"
if [[ ! -d "$CGAL_DIR" ]]; then
  info "Fetching CGAL $CGAL_VERSION..."
  curl -fL "https://github.com/CGAL/cgal/releases/download/v$CGAL_VERSION/CGAL-$CGAL_VERSION.tar.xz" -o .deps/cgal.tar.xz
  tar -C .deps -xf .deps/cgal.tar.xz
  rm -f .deps/cgal.tar.xz
fi

# ---- OpenVDB ---------------------------------------------------------------
VDB_PREFIX="$ROOT/.deps/openvdb"
if [[ ! -f "$VDB_PREFIX/lib/libopenvdb.so" ]]; then
  info "Building OpenVDB $OPENVDB_VERSION (several minutes)..."
  rm -rf .deps/openvdb-src
  git clone --depth 1 --branch "v$OPENVDB_VERSION" https://github.com/AcademySoftwareFoundation/openvdb.git .deps/openvdb-src
  "$CMAKE" -S .deps/openvdb-src -B .build/openvdb -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MAKE_PROGRAM="$NINJA" -DCMAKE_INSTALL_PREFIX="$VDB_PREFIX" -DCMAKE_CXX_STANDARD=17 \
    -DOPENVDB_BUILD_CORE=ON -DOPENVDB_BUILD_BINARIES=OFF -DOPENVDB_BUILD_PYTHON_MODULE=OFF \
    -DOPENVDB_BUILD_UNITTESTS=OFF -DOPENVDB_BUILD_DOCS=OFF -DOPENVDB_BUILD_HOUDINI_PLUGIN=OFF \
    -DOPENVDB_CORE_SHARED=ON -DOPENVDB_CORE_STATIC=OFF -DUSE_BLOSC=OFF -DUSE_ZLIB=ON \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  "$CMAKE" --build .build/openvdb -j "$JOBS"
  "$CMAKE" --install .build/openvdb
fi

# ---- native CPU extensions (wtivo_core, wtivo_vdb) -------------------------
info "Configuring wtivo_core + wtivo_vdb..."
PYBIND_DIR="$("$PY" -m pybind11 --cmakedir)"
"$CMAKE" -S "$ROOT" -B .build/native -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_MAKE_PROGRAM="$NINJA" -DPython3_EXECUTABLE="$PY" -Dpybind11_DIR="$PYBIND_DIR" \
  -DCGAL_DIR="$CGAL_DIR/lib/cmake/CGAL" -DCMAKE_MODULE_PATH="$VDB_PREFIX/lib/cmake/OpenVDB" -DOpenVDB_ROOT="$VDB_PREFIX" \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH="\$ORIGIN;$VDB_PREFIX/lib" \
  -DWTIVO_OUTPUT_DIR="$ROOT/build"
"$CMAKE" --build .build/native -j "$JOBS"

# ---- bundle libopenvdb next to the extensions ($ORIGIN rpath) so build/ is relocatable
cp -a "$VDB_PREFIX"/lib/libopenvdb.so* build/

# ---- CUDA extension (wtivo_gpupr) ------------------------------------------
info "Building wtivo_gpupr for sm_${ARCH/./}..."
WTIVO_CUDA_ARCH="$ARCH" WTIVO_CUDA_HOME="$CUDA_HOME_DIR" "$PY" scripts/build_gpupr.py

# ---- machine-local env file ------------------------------------------------
cat > .wtivo-env.sh <<ENVEOF
# Generated by scripts/setup_ubuntu.sh -- machine-local, do not commit.
export WTIVO_CUDA_HOME="$CUDA_HOME_DIR"
export LD_LIBRARY_PATH="$VDB_PREFIX/lib:$CUDA_HOME_DIR/lib64\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
ENVEOF

# ---- relocatable build manifest (checked by wtivo.py / verify_install.py) ----
"$PY" scripts/write_build_info.py --arch "$ARCH"

info "Verifying install..."
# shellcheck disable=SC1091
. ./.wtivo-env.sh
"$PY" scripts/verify_install.py
info "Done. Run: ./run-wtivo.sh --input model.glb --output model_watertight.glb"
