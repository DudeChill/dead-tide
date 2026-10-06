#!/bin/sh
# Build Dead Tide releases. Usage: tools/build.sh [linux|windows|all]
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TARGET="${1:-all}"

echo "== 1/3 validating project =="
"$GODOT" --headless --path . --quit > /dev/null 2>&1 || { echo "project validation failed"; exit 1; }

echo "== 2/3 running tests =="
./tools/test.sh

echo "== 3/3 exporting =="
mkdir -p builds/linux builds/windows
export_templates="$HOME/.local/share/godot/export_templates/4.7.2.stable"
if [ ! -d "$export_templates" ]; then
  echo "MISSING: export templates at $export_templates"
  echo "Install: download Godot_v4.7.2-stable_export_templates.tpz from"
  echo "https://github.com/godotengine/godot/releases and extract into that directory."
  exit 1
fi

case "$TARGET" in
  linux|all)
    "$GODOT" --headless --path . --export-release "Linux" builds/linux/DeadTide.x86_64
    echo "Linux build: builds/linux/DeadTide.x86_64"
    ;;
esac
case "$TARGET" in
  windows|all)
    "$GODOT" --headless --path . --export-release "Windows Desktop" builds/windows/DeadTide.exe
    echo "Windows build: builds/windows/DeadTide.exe"
    ;;
esac
echo "BUILD OK"