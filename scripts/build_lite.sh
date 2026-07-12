#!/usr/bin/env bash
set -euo pipefail

# Build the app without the jacket images and per-song songs JSONs.
# Song metadata still ships via a single merged assets/songlist.json, which
# the `- assets/` pubspec entry already covers; jackets fall back to a
# placeholder icon in the UI.
#
# Usage: scripts/build_lite.sh [flutter build args...]   (defaults to `apk`)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

"$REPO_ROOT/scripts/generate_songlist.sh"

cp pubspec.yaml pubspec.yaml.orig
trap 'mv pubspec.yaml.orig pubspec.yaml' EXIT

sed -i '' \
  -e '\|- assets/jackets-160/|d' \
  -e '\|- assets/jackets/|d' \
  -e '\|- assets/songs/|d' \
  pubspec.yaml

if [ $# -eq 0 ]; then
  set -- apk
fi
flutter build "$@"
