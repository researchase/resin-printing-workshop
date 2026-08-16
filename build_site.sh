#!/usr/bin/env bash
# Assemble the published site into dist/:
#   /       the landing page (site/)
#   /lab/   the Godot workshop deck (build/web/)
#
# Usage:  ./build_site.sh [--export]
#   --export  re-run the Godot web export first (needs 4.6 export templates)
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-$HOME/apps/Godot_v4.6-stable_linux.x86_64}"

if [[ "${1:-}" == "--export" ]]; then
  echo "==> exporting the Godot web build"
  rm -rf build/web && mkdir -p build/web
  "$GODOT" --headless --path . --export-release "Web" build/web/index.html
fi

if [[ ! -f build/web/index.html ]]; then
  echo "build/web/index.html missing - run: $0 --export" >&2
  exit 1
fi

echo "==> assembling dist/"
rm -rf dist && mkdir -p dist/lab
cp -r site/. dist/
cp -r build/web/. dist/lab/
touch dist/.nojekyll

echo "==> done"
du -sh dist
find dist -maxdepth 2 -type f | head -20
