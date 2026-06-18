#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Qobuz Discord Presence"
PRODUCT_NAME="QobuzDiscordPresence"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp ".build/release/$PRODUCT_NAME" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
cp "macos/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "Built $APP_DIR"
