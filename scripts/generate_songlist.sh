#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Merge every assets/songs/*.json into a single assets/songlist.json array.
# Lite builds (scripts/build_lite.sh) bundle this instead of the per-song files.
# Each song's pattern analysis (~10x the rest of the song) is split out into
# assets/patterns/<name>.json, which the app reads lazily per song.
python3 - "$REPO_ROOT/assets/songs" "$REPO_ROOT/assets/songlist.json" "$REPO_ROOT/assets/patterns" <<'EOF'
import json, pathlib, sys

src, dst, patterns = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
patterns.mkdir(exist_ok=True)
songs = [json.loads(p.read_text(encoding="utf-8")) for p in sorted(src.glob("*.json"))]
for song in songs:
    analysis = song.pop("pattern_analysis", None)
    if analysis is not None:
        (patterns / f"{song['name']}.json").write_text(json.dumps(analysis, separators=(",", ":")), encoding="utf-8")
dst.write_text(json.dumps(songs, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"wrote {dst} ({len(songs)} songs)")
EOF
