#!/bin/bash
# Packages an app into the drag-to-Applications installer DMG:
#
#   scripts/package-dmg.sh releases/0.3.0/Flyby.app releases/0.3.0/Flyby-0.3.0.dmg
#
# A 640×420 window with the drawn background from
# Resources/DMGGenerator/generate.swift, the app on the left, an /Applications
# alias on the right, no toolbar or sidebar, and the app icon as the volume icon.
# The window layout is a .DS_Store that Finder can only write to a mounted,
# read-write image, so this mounts one, arranges it over AppleScript, then
# converts it to a compressed read-only image. Needs a logged-in GUI session
# (Finder does the arranging), so it runs from release.sh, not CI.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC_APP="${1:?usage: scripts/package-dmg.sh <app> <out.dmg>}"
OUT="${2:?usage: scripts/package-dmg.sh <app> <out.dmg>}"
APP_NAME="$(basename "$SRC_APP" .app)"
VOLUME="$APP_NAME"

# Window geometry. These match Resources/DMGGenerator/generate.swift — the
# background art is drawn against exactly this layout, so change both together.
DMG_W=640
DMG_H=420
DMG_ICON_SIZE=128
DMG_APP_X=168
DMG_APP_Y=218
DMG_ALIAS_X=472
DMG_ALIAS_Y=218

if [[ ! -f Resources/dmg-background.tiff ]]; then
  echo "› Drawing the DMG background…"
  swift Resources/DMGGenerator/generate.swift
fi

WORK="$(mktemp -d)"
STAGING="$WORK/staging"
RW="$WORK/rw.dmg"
MOUNT="/Volumes/$VOLUME"
cleanup() {
  if [[ -d "$MOUNT" ]]; then hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$STAGING/.background"
ditto "$SRC_APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
cp Resources/dmg-background.tiff "$STAGING/.background/background.tiff"

# A stale mount from an interrupted run would steal the volume name.
if [[ -d "$MOUNT" ]]; then hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true; fi

# Sized with room to spare: the icon, the layout and Finder's own bookkeeping
# all land after this point, and hdiutil's automatic size leaves almost none.
# The slack costs nothing in the compressed image that ships.
SIZE_MB=$(( $(du -sm "$STAGING" | cut -f1) + 24 ))
hdiutil create -volname "$VOLUME" -srcfolder "$STAGING" -ov \
  -format UDRW -fs HFS+ -size "${SIZE_MB}m" "$RW" >/dev/null
hdiutil attach "$RW" -readwrite -noverify -noautoopen -mountpoint "$MOUNT" >/dev/null

echo "› Arranging the installer window…"
osascript <<APPLESCRIPT >/dev/null
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {320, 160, $((320 + DMG_W)), $((160 + DMG_H))}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $DMG_ICON_SIZE
    set text size of opts to 12
    set label position of opts to bottom
    set shows item info of opts to false
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {$DMG_APP_X, $DMG_APP_Y}
    set position of item "Applications" of container window to {$DMG_ALIAS_X, $DMG_ALIAS_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

# Volume icon last: Finder deletes a .VolumeIcon.icns that appears before it
# has finished with the window, and writing it here survives the convert.
cp "$SRC_APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || echo "  (SetFile unavailable — volume icon skipped)"

chmod -Rf go-w "$MOUNT" 2>/dev/null || true
sync
hdiutil detach "$MOUNT" >/dev/null

rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$OUT"
fi
echo "✓ Packaged $OUT"
