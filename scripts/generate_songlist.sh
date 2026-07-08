#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Merge every assets/song-data/*.json into a single assets/songlist.json array.
# Lite builds (scripts/build_lite.sh) bundle this instead of the per-song files.
python3 - "$REPO_ROOT/assets/song-data" "$REPO_ROOT/assets/songlist.json" <<'EOF'
import json, pathlib, sys

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
songs = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(src.glob("*.json"))]
dst.write_text(json.dumps(songs, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"wrote {dst} ({len(songs)} songs)")
EOF
