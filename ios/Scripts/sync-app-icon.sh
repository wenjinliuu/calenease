#!/usr/bin/env bash
set -euo pipefail

IOS_DIR=$(cd "$(dirname "$0")/.." && pwd)
ROOT_DIR=$(cd "$IOS_DIR/.." && pwd)
SOURCE="$ROOT_DIR/DesignAssets/AppIcon/pixel-grid-check-master.png"
DESTINATION="$IOS_DIR/ShiftLedger/Resources/AppIcon.icon/Assets/PixelGridCheck.png"

test -f "$SOURCE"
mkdir -p "$(dirname "$DESTINATION")"
sips -s format png -z 1024 1024 "$SOURCE" --out "$DESTINATION" >/dev/null

echo "Generated the 1024x1024 AppIcon.icon raster layer."
