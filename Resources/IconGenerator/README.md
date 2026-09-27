# Flyby app icon

`generate.swift` draws the placeholder icon — a glassy magnifying lens with a
comet flying past on a gradient squircle — and emits:

- `Resources/AppIcon.icns` (what the app bundle ships)
- `Resources/IconGenerator/master-1024.png` (git-ignored preview of the master render)

Regenerate after editing the drawing code:

```sh
swift Resources/IconGenerator/generate.swift
```

## Swapping in real artwork later

`build.sh` only regenerates the icns when `Resources/AppIcon.icns` is missing,
so either:

1. Replace `Resources/AppIcon.icns` with your own — done. No code changes.
2. Or, from a 1024×1024 PNG, build an icns yourself:

```sh
mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s art.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) art.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
```
