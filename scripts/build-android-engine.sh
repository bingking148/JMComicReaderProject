#!/bin/sh
# Build the in-process Android engine. Requires the Android SDK/NDK and gomobile.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT="$ROOT/app/android/app/libs/jmengine.aar"
mkdir -p "$(dirname "$OUT")"
if [ -f "$OUT" ]; then
  newer=$(find "$ROOT/engine" -name '*.go' -newer "$OUT" -print -quit || true)
  if [ -z "$newer" ]; then
    exit 0
  fi
fi
if ! command -v go >/dev/null 2>&1; then
  echo "需要安装 Go" >&2
  exit 1
fi
GOBIN=$(go env GOPATH)/bin
export PATH="$PATH:$GOBIN"
# This revision still builds with Go 1.22. Newer gomobile asks for Go 1.26.
MOBILE_REV=c31d5b91ecc32c0d598b8fe8457d244ca0b4e815
if ! command -v gomobile >/dev/null 2>&1; then
  go install "golang.org/x/mobile/cmd/gomobile@${MOBILE_REV}"
  go install "golang.org/x/mobile/cmd/gobind@${MOBILE_REV}"
fi
if ! command -v gomobile >/dev/null 2>&1; then
  echo "gomobile 不在 PATH 中（已尝试 \$GOPATH/bin）" >&2
  exit 1
fi
gomobile init
cd "$ROOT/engine"
# arm64 covers current phones. Add ,android/arm or ,android/amd64 if you need them.
gomobile bind -target=android/arm64 -androidapi 21 -o "$OUT" ./jmengine
echo "android engine -> $OUT"
