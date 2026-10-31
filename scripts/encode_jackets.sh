#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Encode assets/jackets{,-160}/*.png as quality-85 WebP into
# assets/jackets{,-160}-webp/, which the app reads (~86% smaller). The PNGs
# keep publishing for older apps. Only missing or outdated files are encoded,
# and WebPs whose PNG is gone are removed. Run after any change to the jackets;
# needs cwebp (brew install webp).
python3 - "$REPO_ROOT/assets" <<'PY'
import os, pathlib, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

assets = pathlib.Path(sys.argv[1])
jobs = []
for d in ["jackets", "jackets-160"]:
    src, dst = assets / d, assets / f"{d}-webp"
    dst.mkdir(exist_ok=True)
    pngs = {p.stem: p for p in src.glob("*.png")}
    for w in dst.glob("*.webp"):
        if w.stem not in pngs:
            w.unlink()
    for stem, png in pngs.items():
        out = dst / f"{stem}.webp"
        if not out.exists() or out.stat().st_mtime < png.stat().st_mtime:
            jobs.append((png, out))
with ThreadPoolExecutor(os.cpu_count()) as ex:
    list(ex.map(lambda j: subprocess.run(
        ["cwebp", "-quiet", "-q", "85", "-m", "6", str(j[0]), "-o", str(j[1])], check=True), jobs))
print(f"encoded {len(jobs)} jackets")
PY
