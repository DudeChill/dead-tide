#!/bin/sh
# Run Dead Tide (windowed). Pass extra args through, e.g. -- --seed=1234.
cd "$(dirname "$0")/.."
exec godot --path . "$@"