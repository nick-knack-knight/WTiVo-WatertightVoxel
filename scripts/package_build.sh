#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Package the compiled extensions into a relocatable tarball that can be built on one
# machine and unpacked into another WTiVo checkout (or the ComfyUI node's backend/build).
#   scripts/package_build.sh [output.tar.gz]
# Target machine must match BUILD_INFO.json: Python 3.12, same torch minor, same GPU arch,
# and apt libtbb12/libgmp/libmpfr/libboost-iostreams installed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/build"
for m in wtivo_core wtivo_vdb wtivo_gpupr; do
  compgen -G "${m}*.so" >/dev/null || { echo "[ERROR] ${m}*.so missing in build/" >&2; exit 1; }
done
[[ -f BUILD_INFO.json ]] || { echo "[ERROR] BUILD_INFO.json missing; run scripts/write_build_info.py" >&2; exit 1; }
OUT="${1:-$ROOT/wtivo-build-linux.tar.gz}"
tar -czf "$OUT" wtivo_core*.so wtivo_vdb*.so wtivo_gpupr*.so libopenvdb.so* BUILD_INFO.json
echo "[WTiVo] wrote $OUT"; cat BUILD_INFO.json
