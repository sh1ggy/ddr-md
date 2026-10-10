#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:?usage: bash scripts/build_store.sh <ipa|appbundle|apk> [more flutter build args]}"
shift

# Store builds bundle exactly what's live, then point the app at it for
# updates. CONTENT_URL can be given; otherwise it comes from Terraform.
CONTENT_URL="${CONTENT_URL:-$(terraform -chdir="$REPO_ROOT/infra" output -raw content_url)}"
bash "$REPO_ROOT/scripts/fetch_content.sh" "$CONTENT_URL"
cd "$REPO_ROOT"
flutter build "$TARGET" --release --dart-define=CONTENT_URL="$CONTENT_URL" "$@"
