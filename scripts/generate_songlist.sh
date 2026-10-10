#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Merge every assets/songs/*.json into a single assets/songlist.json array.
# Lite builds (scripts/build_lite.sh) bundle this instead of the per-song files.
# Prep's own pattern_analysis (~10x the rest of the song) is dropped: the app
# reads assets/patterns/, written by tool/generate_patterns.dart.
python3 - "$REPO_ROOT/assets/songs" "$REPO_ROOT/assets/songlist.json" <<'EOF'
import json, pathlib, sys

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
songs = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(src.glob("*.json"))]
for song in songs:
    song.pop("pattern_analysis", None)
dst.write_text(json.dumps(songs, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"wrote {dst} ({len(songs)} songs)")
EOF
