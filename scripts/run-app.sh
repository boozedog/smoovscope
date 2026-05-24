#!/usr/bin/env bash
# Build and run the macOS app from the command line.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -d "app/smoovscope.xcodeproj" ]]; then
  echo "==> generating Xcode project"
  (cd app && xcodegen generate)
fi

echo "==> building smoovscope"
xcodebuild \
  -project app/smoovscope.xcodeproj \
  -scheme smoovscope \
  -configuration Debug \
  -derivedDataPath app/DerivedData \
  build

APP_PATH="app/DerivedData/Build/Products/Debug/smoovscope.app"

echo "==> launching ${APP_PATH}"
open "${APP_PATH}"
