#!/usr/bin/env bash
set -euo pipefail

IOS_DIR=$(cd "$(dirname "$0")/.." && pwd)
ROOT_DIR=$(cd "$IOS_DIR/.." && pwd)
SOURCE_DIR="$ROOT_DIR/DesignAssets/AppIcon"
ASSET_DIR="$IOS_DIR/CalenEase/Resources/AppIcon.icon/Assets"

mkdir -p "$ASSET_DIR"
cp "$SOURCE_DIR/calendar-background.svg" "$ASSET_DIR/CalendarBackground.svg"
cp "$SOURCE_DIR/calendar-header.svg" "$ASSET_DIR/CalendarHeader.svg"
cp "$SOURCE_DIR/date-dots.svg" "$ASSET_DIR/DateDots.svg"
cp "$SOURCE_DIR/active-day.svg" "$ASSET_DIR/ActiveDay.svg"

echo "Synced four 1024x1024 SVG layers into AppIcon.icon."
