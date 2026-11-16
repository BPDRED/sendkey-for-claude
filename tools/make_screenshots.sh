#!/bin/bash
# Re-draws the README images in docs/ (light and dark) from the app's real menu
# rows and icons. Run it after changing the menu or the icons.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O -parse-as-library -o build/make_screenshots \
    Sources/Icons.swift Sources/MenuRows.swift Sources/KeyMap.swift tools/make_screenshots.swift
build/make_screenshots docs
