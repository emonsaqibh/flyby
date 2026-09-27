# Flyby installer background

`generate.swift` draws the window art for the drag-to-Applications disk image
and emits:

- `Resources/dmg-background.tiff` — what the DMG ships (multi-representation,
  so Finder picks @2x on Retina)
- `Resources/dmg-background.png` / `@2x.png` (git-ignored) — the individual renders, handy for
  eyeballing a change without building a DMG

Regenerate after editing the drawing code:

```sh
swift Resources/DMGGenerator/generate.swift
```

`build.sh --dmg` only generates it when the TIFF is missing, so a hand-made
replacement survives rebuilds.

## Layout is shared with build.sh

The art is drawn against a fixed window geometry, and `build.sh` tells Finder to
use the same one. Change one and change the other — the generator prints the
numbers it used:

| | |
| --- | --- |
| Window | 640 × 420 |
| Icon size | 128 |
| `Flyby.app` | (168, 218) |
| `Applications` | (472, 218) |

Coordinates are Finder's: top-left origin, y increasing downward, positions
naming the *centre* of an icon. The generator flips once on the way into
CoreGraphics so the constants at the top of the file read the same as the
AppleScript.

## Why there are no frames around the icon slots

Finder draws the filename under each icon and we don't control its colour — it
follows the viewer's light/dark appearance. Anything with a hard edge behind the
label reads as broken in one of the two modes, so the slots are lit with soft
white glows on a light background instead, and the labels land on plain paper.
