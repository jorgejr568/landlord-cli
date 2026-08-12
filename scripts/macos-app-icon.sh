#!/usr/bin/env bash
# Regenerates macos/Rentivo/Resources/Assets.xcassets/AppIcon.appiconset from the iOS app icon.
#
# The iOS catalog holds the single source of truth for the artwork (one 1024x1024 PNG). macOS needs
# ten sized PNGs laid out on the Apple icon grid, so this script derives them rather than keeping a
# second copy of the artwork. It is idempotent: re-running it leaves the working tree unchanged.
set -euo pipefail

unset CDPATH
repo_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
source_icon="$repo_root/ios/Rentivo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
output_dir="$repo_root/macos/Rentivo/Resources/Assets.xcassets/AppIcon.appiconset"
renderer="$repo_root/scripts/macos-app-icon.swift"

if [ ! -f "$source_icon" ]; then
  echo "missing source icon: $source_icon" >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  echo "swift is required; install the Xcode command line tools" >&2
  exit 1
fi

mkdir -p "$output_dir"
swift "$renderer" "$source_icon" "$output_dir"
