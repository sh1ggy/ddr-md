#!/usr/bin/env bash
# Run the macOS app from this checkout without touching any other checkout's.
#
#   bash scripts/run_macos.sh [more flutter run args]
#
# A worktree builds as its own app, com.shiggy.ddrmd.<worktree>: its own
# container (database, preferences, keychain items) and its own window, which
# screen-control tools address by that bundle id. Its database starts as a
# copy of the main app's seeded timing-preview.db. The main checkout keeps
# com.shiggy.ddrmd.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [ "$(git rev-parse --git-dir)" = "$(git rev-parse --git-common-dir)" ]; then
  rm -f macos/Runner/Configs/Worktree.xcconfig
  exec flutter run -d macos --dart-define=DB_NAME=timing-preview.db "$@"
fi

id="com.shiggy.ddrmd.$(basename "$PWD" | tr -c 'A-Za-z0-9\n' '-')"
echo "PRODUCT_BUNDLE_IDENTIFIER = $id" > macos/Runner/Configs/Worktree.xcconfig

seed="$HOME/Library/Containers/com.shiggy.ddrmd/Data/Documents/timing-preview.db"
docs="$HOME/Library/Containers/$id/Data/Documents"
if [ ! -e "$docs/timing-preview.db" ] && [ -e "$seed" ]; then
  mkdir -p "$docs"
  cp "$seed" "$docs/timing-preview.db"
fi

echo "Running as $id"
exec flutter run -d macos --dart-define=DB_NAME=timing-preview.db "$@"
