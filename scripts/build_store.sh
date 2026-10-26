#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:?usage: bash scripts/build_store.sh <ipa|appbundle|apk> [more flutter build args]}"
shift

# Store builds bundle exactly what's live, then point the app at it for
# updates. CONTENT_URL can be given; otherwise it comes from Terraform.
CONTENT_URL="${CONTENT_URL:-$(terraform -chdir="$REPO_ROOT/infra" output -raw content_url)}"
# Cloud sync's server likewise; empty (no workers_subdomain set) leaves it off.
SYNC_URL="${SYNC_URL:-$(terraform -chdir="$REPO_ROOT/infra" output -raw sync_url 2>/dev/null || true)}"
bash "$REPO_ROOT/scripts/fetch_content.sh" "$CONTENT_URL"
cd "$REPO_ROOT"
flutter build "$TARGET" --release --dart-define=CONTENT_URL="$CONTENT_URL" --dart-define=SYNC_URL="$SYNC_URL" "$@"
