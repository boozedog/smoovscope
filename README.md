# smoovscope

All-in-one macOS app for collecting and viewing OpenTelemetry traces locally during development.

## Architecture

- **SwiftUI app** (`app/`) — native macOS UI, minimum target macOS 26 Tahoe
- **Go sidecar** (`sidecar/`) — embedded OTLP/HTTP receiver on `127.0.0.1:4318`, writes spans to SQLite
- **SQLite** — single source of truth, also the bus between sidecar and UI (UI polls for new rows)

```
smoovscope.app/
  Contents/
    MacOS/smoovscope          (SwiftUI app)
    Resources/otlp-receiver   (Go sidecar, universal binary)
```

## Build

```sh
# One-time
brew install xcodegen
(cd app && xcodegen generate)

# Build sidecar (universal binary into app/Resources/)
make sidecar

# Open in Xcode
open app/smoovscope.xcodeproj
```

## Send a test span

With the app running (or just the sidecar via `make run-sidecar`):

```sh
# TODO: example curl with OTLP protobuf payload
```

## Layout

```
sidecar/         Go OTLP receiver
app/             SwiftUI app + xcodegen project.yml
scripts/         build-sidecar.sh (universal binary)
```
