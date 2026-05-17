#!/usr/bin/env bash
# Build a universal (arm64 + amd64) macOS binary of the Go sidecar
# and drop it into app/Resources/ for Xcode to bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="app/Resources"
ARM_BIN="sidecar/bin/otlp-receiver-arm64"
AMD_BIN="sidecar/bin/otlp-receiver-amd64"
UNI_BIN="${OUT_DIR}/otlp-receiver"

mkdir -p "sidecar/bin" "${OUT_DIR}"

echo "==> building arm64"
(cd sidecar && GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "../${ARM_BIN}" .)

echo "==> building amd64"
(cd sidecar && GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "../${AMD_BIN}" .)

echo "==> lipo into universal binary"
lipo -create -output "${UNI_BIN}" "${ARM_BIN}" "${AMD_BIN}"
chmod +x "${UNI_BIN}"

echo "==> done: ${UNI_BIN}"
file "${UNI_BIN}"
