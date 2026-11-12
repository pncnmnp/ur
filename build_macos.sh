#!/bin/zsh
# Build the macOS app: build/macos/Royal Game of Ur.app
# Needs Godot 4.7.2 export templates installed (Editor > Manage Export Templates).
set -euo pipefail
# Set GODOT to use a Godot binary that is not in /Applications.
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ROOT="${0:A:h}"
OUT="$ROOT/build/macos"
NAME="Royal Game of Ur"

mkdir -p "$OUT"
rm -rf "$OUT/$NAME.app" "$OUT/$NAME.zip"
"$GODOT" --headless --path "$ROOT" --import
"$GODOT" --headless --path "$ROOT" --export-release "macOS" "$OUT/$NAME.zip"
# Unpack the .app next to the zip so it can be double-clicked straight from the repo.
ditto -x -k "$OUT/$NAME.zip" "$OUT"
xattr -cr "$OUT/$NAME.app" 2>/dev/null || true
rm -f "$OUT/$NAME.zip"
# Apple Silicon only: drop the Intel slice (halves the size, keeps it under GitHub's 100 MB file limit),
# then re-sign ad-hoc since thinning invalidates the signature.
BIN="$OUT/$NAME.app/Contents/MacOS/$NAME"
lipo "$BIN" -thin arm64 -output "$BIN.arm64" && mv "$BIN.arm64" "$BIN"
codesign --force --deep --sign - "$OUT/$NAME.app"
echo "Built: $OUT/$NAME.app"
