#!/usr/bin/env swift
// Generates Resources/AppIcon.icns (and a master PNG) for Flyby.
//
// Placeholder art: a glassy magnifying lens with a comet sweeping past it —
// the "flyby" — on a gradient squircle, after the macOS 26 / iOS 26 icon
// language. To swap in real artwork later, either replace this drawing code
// or just drop a finished AppIcon.icns into Resources/ (build.sh only
// regenerates the icns when it's missing).
//
// Run from the repo root:  swift Resources/IconGenerator/generate.swift [--dev]
// (--dev writes Resources/AppIcon-Dev.icns: the same icon on a sunset sky.)

import AppKit
import CoreGraphics

// MARK: - Canvas

let size: CGFloat = 1024

func makeContext(_ pixels: Int) -> CGContext {
    CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: colors as CFArray,
        locations: locations
    )!
}

let ctx = makeContext(Int(size))

// MARK: - Squircle plate
// The standard macOS icon grid: an 824 pt rounded square centred in 1024,
// with everything else transparent margin.

let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(
    roundedRect: plate,
    cornerWidth: 185,
    cornerHeight: 185,
    transform: nil
)

// MARK: - Flavor
// `--dev` draws the same icon on a sunset sky and writes AppIcon-Dev.icns, so
// the dev build (`./build.sh`) is obvious at a glance next to the installed
// release in the menu bar's neighbours, Finder and System Settings.

let isDev = CommandLine.arguments.contains("--dev")

struct Palette {
    var plate: CGColor
    var sky: [CGColor]
    var glow: CGColor
}

let palette = isDev
    ? Palette(
        plate: rgba(0.55, 0.22, 0.10),
        sky: [rgba(1.0, 0.80, 0.42), rgba(0.97, 0.52, 0.16), rgba(0.66, 0.20, 0.18)],
        glow: rgba(1.0, 0.93, 0.75)
    )
    : Palette(
        plate: rgba(0.15, 0.2, 0.6),
        sky: [rgba(0.42, 0.72, 1.0), rgba(0.22, 0.42, 0.95), rgba(0.13, 0.15, 0.62)],
        glow: rgba(0.75, 0.92, 1.0)
    )

// Soft drop shadow behind the plate, like real macOS icons ship with.
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -12),
    blur: 36,
    color: rgba(0, 0, 0.1, 0.35)
)
ctx.addPath(platePath)
ctx.setFillColor(palette.plate)
ctx.fillPath()
ctx.restoreGState()

// Everything from here on stays inside the squircle.
ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()

// Sky gradient: airy azure at the top falling into deep indigo (a sunset,
// for the dev build).
ctx.drawLinearGradient(
    gradient(palette.sky, [0, 0.52, 1]),
    start: CGPoint(x: 512, y: plate.maxY),
    end: CGPoint(x: 512, y: plate.minY),
    options: []
)

// A wide glow high in the "sky" so the top half feels lit.
ctx.drawRadialGradient(
    gradient([palette.glow.copy(alpha: 0.55)!, palette.glow.copy(alpha: 0)!], [0, 1]),
    startCenter: CGPoint(x: 400, y: 830), startRadius: 0,
    endCenter: CGPoint(x: 400, y: 830), endRadius: 560,
    options: []
)

// MARK: - Comet geometry
// The comet rides a shallow Bézier bow that clears the top of the lens —
// close enough to feel like a flyby, without ever crossing the glass.

let cometTail = CGPoint(x: 150, y: 620)
let cometPeak = CGPoint(x: 500, y: 1000)   // control point, pulls the arc up
let cometHead = CGPoint(x: 815, y: 775)

func cometPoint(_ t: CGFloat) -> CGPoint {
    let u = 1 - t
    return CGPoint(
        x: u * u * cometTail.x + 2 * u * t * cometPeak.x + t * t * cometHead.x,
        y: u * u * cometTail.y + 2 * u * t * cometPeak.y + t * t * cometHead.y
    )
}

/// The trail is dabbed as overlapping discs that shrink and fade toward the
/// tail — an easy way to get a taper CoreGraphics won't do with one stroke.
func drawTrail() {
    let steps = 200
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)          // 0 = tail, 1 = head
        let p = cometPoint(t)
        let radius = 2.5 + 15 * pow(t, 1.5)
        let alpha = 0.9 * pow(t, 1.9)
        ctx.setFillColor(rgba(1, 1, 1, alpha))
        ctx.fillEllipse(in: CGRect(
            x: p.x - radius, y: p.y - radius,
            width: radius * 2, height: radius * 2
        ))
    }
}

// MARK: - Magnifying lens

let lensCenter = CGPoint(x: 450, y: 530)
let ringRadius: CGFloat = 178              // centreline of the ring stroke
let ringWidth: CGFloat = 58

// Glass fill inside the lens: barely-there white that brightens at the top.
ctx.saveGState()
ctx.addEllipse(in: CGRect(
    x: lensCenter.x - ringRadius, y: lensCenter.y - ringRadius,
    width: ringRadius * 2, height: ringRadius * 2
))
ctx.clip()
ctx.drawLinearGradient(
    gradient([rgba(1, 1, 1, 0.28), rgba(1, 1, 1, 0.05)], [0, 1]),
    start: CGPoint(x: lensCenter.x, y: lensCenter.y + ringRadius),
    end: CGPoint(x: lensCenter.x, y: lensCenter.y - ringRadius),
    options: []
)
// Specular sweep across the upper-left of the glass.
ctx.drawRadialGradient(
    gradient([rgba(1, 1, 1, 0.35), rgba(1, 1, 1, 0)], [0, 1]),
    startCenter: CGPoint(x: lensCenter.x - 70, y: lensCenter.y + 90), startRadius: 0,
    endCenter: CGPoint(x: lensCenter.x - 70, y: lensCenter.y + 90), endRadius: 190,
    options: []
)
ctx.restoreGState()

/// Strokes the ring and handle. Drawn twice: a blurred dark pass for depth,
/// then the white glass pass on top.
func drawMagnifier(shadow: Bool) {
    ctx.saveGState()
    if shadow {
        ctx.setShadow(
            offset: CGSize(width: 0, height: -10),
            blur: 26,
            color: rgba(0.05, 0.08, 0.35, 0.45)
        )
    }

    // Ring.
    ctx.setStrokeColor(rgba(1, 1, 1, shadow ? 0.001 : 1))
    ctx.setLineWidth(ringWidth)
    ctx.strokeEllipse(in: CGRect(
        x: lensCenter.x - ringRadius, y: lensCenter.y - ringRadius,
        width: ringRadius * 2, height: ringRadius * 2
    ))

    // Handle, pointing down-right.
    let dir = CGPoint(x: cos(-.pi / 4), y: sin(-.pi / 4))
    let start = CGPoint(
        x: lensCenter.x + dir.x * (ringRadius + ringWidth / 2 - 6),
        y: lensCenter.y + dir.y * (ringRadius + ringWidth / 2 - 6)
    )
    let end = CGPoint(
        x: lensCenter.x + dir.x * (ringRadius + 218),
        y: lensCenter.y + dir.y * (ringRadius + 218)
    )
    ctx.setLineWidth(78)
    ctx.setLineCap(.round)
    ctx.move(to: start)
    ctx.addLine(to: end)
    ctx.strokePath()
    ctx.restoreGState()
}

// Depth pass: stroke transparently but let the shadow paint.
drawMagnifier(shadow: true)

// Glass pass: white ring + handle with a shared vertical sheen. Filled in two
// clip passes — a single even-odd mask punches a hole wherever the handle
// overlaps the ring band.
let glassSheen = gradient(
    [rgba(1, 1, 1, 1), rgba(0.82, 0.9, 1.0, 0.92)], [0, 1]
)
let sheenTop = CGPoint(x: lensCenter.x, y: lensCenter.y + ringRadius + ringWidth)
let sheenBottom = CGPoint(x: lensCenter.x, y: lensCenter.y - ringRadius - 240)

ctx.saveGState()
let ringMask = CGMutablePath()
ringMask.addEllipse(in: CGRect(
    x: lensCenter.x - ringRadius - ringWidth / 2,
    y: lensCenter.y - ringRadius - ringWidth / 2,
    width: (ringRadius + ringWidth / 2) * 2,
    height: (ringRadius + ringWidth / 2) * 2
))
ringMask.addEllipse(in: CGRect(
    x: lensCenter.x - ringRadius + ringWidth / 2,
    y: lensCenter.y - ringRadius + ringWidth / 2,
    width: (ringRadius - ringWidth / 2) * 2,
    height: (ringRadius - ringWidth / 2) * 2
))
ctx.addPath(ringMask)
ctx.clip(using: .evenOdd)
ctx.drawLinearGradient(glassSheen, start: sheenTop, end: sheenBottom, options: [])
ctx.restoreGState()

ctx.saveGState()
let dir = CGPoint(x: cos(-.pi / 4), y: sin(-.pi / 4))
let handle = CGMutablePath()
handle.move(to: CGPoint(
    x: lensCenter.x + dir.x * (ringRadius + ringWidth / 2 - 6),
    y: lensCenter.y + dir.y * (ringRadius + ringWidth / 2 - 6)
))
handle.addLine(to: CGPoint(
    x: lensCenter.x + dir.x * (ringRadius + 218),
    y: lensCenter.y + dir.y * (ringRadius + 218)
))
ctx.addPath(handle.copy(
    strokingWithWidth: 78, lineCap: .round, lineJoin: .round, miterLimit: 10
))
ctx.clip()
ctx.drawLinearGradient(glassSheen, start: sheenTop, end: sheenBottom, options: [])
ctx.restoreGState()

// MARK: - Comet

drawTrail()

ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 34, color: rgba(1, 1, 1, 0.9))
ctx.setFillColor(rgba(1, 1, 1, 1))
ctx.fillEllipse(in: CGRect(
    x: cometHead.x - 23, y: cometHead.y - 23, width: 46, height: 46
))
ctx.restoreGState()

// A couple of faint companion stars so the sky doesn't feel empty.
for (x, y, r, a) in [(252.0, 292.0, 6.0, 0.5), (795.0, 415.0, 5.0, 0.4)] {
    ctx.setFillColor(rgba(1, 1, 1, a))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// MARK: - Plate finishing: top sheen and rim light

ctx.drawLinearGradient(
    gradient([rgba(1, 1, 1, 0.16), rgba(1, 1, 1, 0)], [0, 1]),
    start: CGPoint(x: 512, y: plate.maxY),
    end: CGPoint(x: 512, y: plate.maxY - 300),
    options: []
)

ctx.restoreGState()   // squircle clip

ctx.saveGState()
ctx.addPath(CGPath(
    roundedRect: plate.insetBy(dx: 3, dy: 3),
    cornerWidth: 182, cornerHeight: 182, transform: nil
))
ctx.setStrokeColor(rgba(1, 1, 1, 0.22))
ctx.setLineWidth(3)
ctx.strokePath()
ctx.restoreGState()

// MARK: - Output

let master = ctx.makeImage()!
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
let resources = scriptDir.deletingLastPathComponent()

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func resized(_ image: CGImage, to pixels: Int) -> CGImage {
    let ctx = makeContext(pixels)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return ctx.makeImage()!
}

let outputName = isDev ? "AppIcon-Dev" : "AppIcon"
writePNG(master, to: scriptDir.appendingPathComponent(isDev ? "master-dev-1024.png" : "master-1024.png"))

let iconset = resources.appendingPathComponent("\(outputName).iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, pixels) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    writePNG(resized(master, to: pixels), to: iconset.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns", iconset.path,
    "-o", resources.appendingPathComponent("\(outputName).icns").path,
]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
try? FileManager.default.removeItem(at: iconset)

print("✓ Wrote Resources/\(outputName).icns")
