#!/bin/sh
# Build the desktop/CLI engine into app/bin so Flutter can launch it.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/app/bin"
cd "$ROOT/engine"
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "$ROOT/app/bin/jmengine" ./cmd/jmengine
echo "engine -> $ROOT/app/bin/jmengine"
