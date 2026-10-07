# SPDX-License-Identifier: GPL-3.0-or-later
"""Write build/BUILD_INFO.json describing the ABI the extensions were built for."""
from __future__ import annotations

import argparse
import json
import platform
import sys
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[1]


def current_info(arch: str = "") -> dict:
    return {
        "python": f"{sys.version_info.major}.{sys.version_info.minor}",
        "torch": torch.__version__.split("+")[0],
        "torch_cuda": torch.version.cuda,
        "cuda_arch": arch,
        "machine": platform.machine(),
        "system": platform.system(),
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--arch", default="")
    ap.add_argument("--build-dir", default=str(ROOT / "build"))
    a = ap.parse_args()
    out = Path(a.build_dir) / "BUILD_INFO.json"
    out.write_text(json.dumps(current_info(a.arch), indent=2) + "\n")
    print(f"[WTiVo] wrote {out}")
