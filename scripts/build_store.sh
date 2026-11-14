#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:?usage: bash scripts/build_store.sh <ipa|appbundle|apk> [more flutter build args]}"
shift

# Store builds bundle exactly what's live, then point the app at it for
# updates. CONTENT_URL can be given; otherwise it comes from Terraform.
CONTENT_URL="${CONTENT_URL:-$(terraform -chdir="$REPO_ROOT/infra" output -raw content_url)}"
# Cloud sync's server likewise; without the output the app's own default
# (the live server) stands.
SYNC_URL="${SYNC_URL:-$(terraform -chdir="$REPO_ROOT/infra" output -raw sync_url 2>/dev/null || true)}"
bash "$REPO_ROOT/scripts/fetch_content.sh" "$CONTENT_URL"
cd "$REPO_ROOT"

# Smaller installs: steps go in gzipped (~153 MB -> ~18 MB on the phone,
# ContentStore unzips), and Song ID's fingerprints stay out (~38 MB less to
# download) until a player asks for them.
python3 - assets/steps assets/steps-gz <<'PY'
import gzip, pathlib, sys

src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
dst.mkdir(exist_ok=True)
names = {p.name + ".gz" for p in src.glob("*.json")}
for p in dst.glob("*.gz"):
    if p.name not in names:
        p.unlink()
for p in src.glob("*.json"):
    out = dst / (p.name + ".gz")
    if not out.exists() or out.stat().st_mtime < p.stat().st_mtime:
        out.write_bytes(gzip.compress(p.read_bytes(), 9, mtime=0))
PY
cp pubspec.yaml pubspec.yaml.orig
trap 'mv pubspec.yaml.orig pubspec.yaml' EXIT
sed -i '' \
  -e 's|- assets/steps/$|- assets/steps-gz/|' \
  -e '\|- assets/fingerprints/|d' \
  pubspec.yaml
flutter build "$TARGET" --release --dart-define=CONTENT_URL="$CONTENT_URL" ${SYNC_URL:+--dart-define=SYNC_URL="$SYNC_URL"} "$@"
