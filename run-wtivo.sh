#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Linux launcher (counterpart of Run-WTiVo.cmd).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[[ -f .wtivo-env.sh ]] && . ./.wtivo-env.sh
[[ -x .venv/bin/python ]] || { echo "[ERROR] .venv not found. Run scripts/setup_ubuntu.sh first." >&2; exit 1; }
for m in wtivo_core wtivo_vdb wtivo_gpupr; do
  compgen -G "build/${m}*.so" >/dev/null || { echo "[ERROR] $m extension not found. Run scripts/setup_ubuntu.sh first." >&2; exit 1; }
done
exec .venv/bin/python -I wtivo.py "$@"
