#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONTENT_URL="${1:?usage: bash scripts/fetch_content.sh <CONTENT_URL>}"

# Make assets/ exactly the live publish (songlist, steps, patterns, jackets,
# manifest) before a store build, so installs start in sync with it rather than
# re-downloading what they already bundle. Files that already match are kept.
python3 - "$CONTENT_URL" "$REPO_ROOT/assets" <<'PY'
import hashlib, json, pathlib, sys, urllib.request

base, assets = sys.argv[1].rstrip("/") + "/", pathlib.Path(sys.argv[2])
# Cloudflare turns away Python's default user agent.
ua = {"User-Agent": "ddr-md-fetch-content"}
manifest = urllib.request.urlopen(urllib.request.Request(base + "manifest.json", headers=ua)).read()
files = json.loads(manifest)["files"]
fetched = 0
for path, sha in files.items():
    dest = assets / path
    if dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest() == sha:
        continue
    name = sha + pathlib.PurePosixPath(path).suffix
    data = urllib.request.urlopen(urllib.request.Request(base + "objects/" + name, headers=ua)).read()
    if hashlib.sha256(data).hexdigest() != sha:
        sys.exit(f"{path}: downloaded file failed its hash")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    fetched += 1
(assets / "content_manifest.json").write_bytes(manifest)
print(f"content {json.loads(manifest)['content']}: fetched {fetched} of {len(files)} files")
PY
