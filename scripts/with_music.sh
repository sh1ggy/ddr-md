#!/usr/bin/env bash
set -euo pipefail

# Personal builds only: bundle each listed song's audio from DDR-BPM-prep/data,
# for the developer's own devices. Never for distribution, so store targets are
# refused. Run fetch_content.sh first so the song list is the live one.
#
# Usage: bash scripts/with_music.sh run -d <device> --release
#        bash scripts/with_music.sh build ios --release

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

for arg in "$@"; do
  case "$arg" in
    ipa|appbundle) echo "with_music.sh: refusing a store build ($arg)" >&2; exit 1 ;;
  esac
done

rm -rf assets/music
mkdir assets/music
python3 - <<'PY'
import json, pathlib

listed = json.load(open("assets/songlist.json"))
songs = {song["name"] for song in (listed if isinstance(listed, list) else listed["songs"])}
linked = 0
for audio in pathlib.Path("DDR-BPM-prep/data").resolve().rglob("*.ogg"):
    link = pathlib.Path("assets/music") / f"{audio.stem}-song.ogg"
    if audio.stem in songs and audio.stat().st_size > 0 and not link.exists():
        link.symlink_to(audio)
        linked += 1
print(f"with_music: {linked} of {len(songs)} songs")
PY

cp pubspec.yaml pubspec.yaml.orig
trap 'mv pubspec.yaml.orig pubspec.yaml' EXIT

sed -i '' -e 's|^    - assets/audio/$|&\
    - assets/music/|' pubspec.yaml

flutter "$@"
