#!/usr/bin/env bash
# Reseed the TestMedia folder to a pristine state from Seeds/ so the app can be
# tested from a clean slate after every rebuild.
#
# - Clears TestMedia's contents but keeps the directory itself, so the app's
#   saved security-scoped bookmark stays valid and the folder stays selected.
# - Clears Mandoline's SwiftData store so previously kept/trashed files are no
#   longer marked "processed" and will be presented again.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEEDS_DIR="$ROOT_DIR/Seeds"
TEST_MEDIA_DIR="$ROOT_DIR/TestMedia"

BUNDLE_ID="com.rowan.Mandoline"
APP_SUPPORT="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support"

if [ ! -d "$SEEDS_DIR" ]; then
  echo "[reseed] No Seeds/ directory found at $SEEDS_DIR; skipping." >&2
  exit 0
fi

# Reset TestMedia contents (keep the directory so the bookmark/inode survives).
mkdir -p "$TEST_MEDIA_DIR"
find "$TEST_MEDIA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

# Copy pristine media back in.
cp "$SEEDS_DIR"/* "$TEST_MEDIA_DIR"/ 2>/dev/null || true

# Wipe the app's processed-file store so the reseeded media is shown again.
if [ -d "$APP_SUPPORT" ]; then
  rm -f "$APP_SUPPORT"/default.store "$APP_SUPPORT"/default.store-shm "$APP_SUPPORT"/default.store-wal
fi

COUNT=$(find "$TEST_MEDIA_DIR" -maxdepth 1 -type f ! -name ".*" | wc -l | tr -d ' ')
echo "[reseed] TestMedia reset with $COUNT media file(s); processed-file store cleared."
