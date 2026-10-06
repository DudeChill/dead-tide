#!/bin/sh
# Headless automated tests. Exit code 0 = all pass.
cd "$(dirname "$0")/.."
echo "== smoke tests =="
godot --headless --path . -- --test
SMOKE=$?
echo "== generation validation (100 seeds) =="
godot --headless --path . -- --testgen
GEN=$?
if [ "$SMOKE" -ne 0 ] || [ "$GEN" -ne 0 ]; then
  echo "TESTS FAILED (smoke=$SMOKE gen=$GEN)"
  exit 1
fi
echo "ALL TESTS PASSED"