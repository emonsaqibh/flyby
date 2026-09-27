#!/usr/bin/env swift
// Draws the disk-image background for Flyby's installer window.
//
// The DMG is the first thing anyone sees of the app, so it's drawn in the same
// language as the icon: pale sky, a comet arc, the indigo-to-azure accent. The
// two icon slots are lit with soft glows rather than framed boxes — a frame
// would collide with the filename labels Finder draws underneath the icons,
// which we don't control.
//
// Everything is laid out in Finder's coordinate space (top-left origin, y down)
// and flipped once on the way into CoreGraphics, so the numbers here can be
// pasted straight into build.sh's AppleScript.
//
// Run from the repo root:  swift Resources/DMGGenerator/generate.swift

import AppKit
import CoreGraphics

// MARK: - Layout
// Shared with build.sh — change one and change the other.

let W: CGFloat = 640
let H: CGFloat = 420

let appSlot = CGPoint(x: 168, y: 218)          // centre of the Flyby.app icon
let applicationsSlot = CGPoint(x: 472, y: 218) // centre of the /Applications alias
let iconSize: CGFloat = 128

// MARK: - Palette

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let ink = rgba(0.09, 0.12, 0.33)
let azure = rgba(0.42, 0.72, 1.0)
let indigo = rgba(0.16, 0.24, 0.78)

func nsColor(_ c: CGColor) -> NSColor { NSColor(cgColor: c)! }

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: colors as CFArray,
        locations: locations
    )!
}

// MARK: - Drawing

/// Renders the whole background at `scale`, in points, into a fresh context.
func render(scale: CGFloat) -> CGImage {
    let ctx = CGContext(
        data: nil,
        width: Int(W * scale),
        height: Int(H * scale),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high

    let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics

    /// Finder-space (y down) → CoreGraphics-space (y up).
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: H - y) }

    // Paper: a barely-there wash from white down to pale sky.
    ctx.drawLinearGradient(
        gradient([rgba(0.99, 0.99, 1.0), rgba(0.91, 0.94, 0.99)], [0, 1]),
        start: p(0, 0), end: p(0, H), options: []
    )

    // Sky glow behind the header, top-left, the same one the icon has.
    ctx.drawRadialGradient(
        gradient([rgba(0.55, 0.78, 1.0, 0.30), rgba(0.55, 0.78, 1.0, 0)], [0, 1]),
        startCenter: p(150, 40), startRadius: 0,
        endCenter: p(150, 40), endRadius: 340,
        options: []
    )

    // MARK: Comet
    // A shallow bow across the top-right, tail dissolving toward the wordmark.

    let tail = p(318, 122), peak = p(498, 14), head = p(592, 66)
    func cometPoint(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * tail.x + 2 * u * t * peak.x + t * t * head.x,
            y: u * u * tail.y + 2 * u * t * peak.y + t * t * head.y
        )
    }
    for i in 0...160 {
        let t = CGFloat(i) / 160
        let q = cometPoint(t)
        let radius = 0.8 + 3.6 * pow(t, 1.6)
        ctx.setFillColor(azure.copy(alpha: 0.42 * pow(t, 1.8))!)
        ctx.fillEllipse(in: CGRect(x: q.x - radius, y: q.y - radius, width: radius * 2, height: radius * 2))
    }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 12, color: azure.copy(alpha: 0.55)!)
    ctx.setFillColor(azure.copy(alpha: 0.85)!)
    ctx.fillEllipse(in: CGRect(x: head.x - 5, y: head.y - 5, width: 10, height: 10))
    ctx.restoreGState()

    // A couple of faint stars, as on the icon.
    for (x, y, r, a) in [(452.0, 62.0, 2.2, 0.35), (566.0, 128.0, 1.8, 0.28)] {
        ctx.setFillColor(indigo.copy(alpha: a)!)
        let c = p(x, y)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    // MARK: Text

    func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// `top` is the top edge of the text box in Finder coordinates.
    func centredText(_ string: String, top: CGFloat, font: NSFont, color: CGColor) {
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font,
            .foregroundColor: nsColor(color),
            .kern: font.pointSize > 24 ? 0.4 : 0,
        ])
        let size = attributed.size()
        let origin = p((W - size.width) / 2, top + size.height)
        attributed.draw(at: origin)
    }

    centredText("Flyby", top: 40, font: rounded(38, .bold), color: ink)
    centredText(
        "Drag Flyby into your Applications folder",
        top: 92, font: rounded(15, .medium), color: ink.copy(alpha: 0.66)!
    )
    centredText(
        "Then open it from Launchpad — Flyby lives in the menu bar, not the Dock.",
        top: 344, font: rounded(11.5, .regular), color: ink.copy(alpha: 0.42)!
    )

    // MARK: Icon slots
    // Soft light under each icon rather than a frame: a frame would collide
    // with the filename label Finder draws under the icon, and the label has to
    // stay readable in both light and dark Finder appearances.

    for slot in [appSlot, applicationsSlot] {
        let c = p(slot.x, slot.y)
        ctx.drawRadialGradient(
            gradient([rgba(1, 1, 1, 0.95), rgba(1, 1, 1, 0)], [0, 1]),
            startCenter: c, startRadius: 0, endCenter: c, endRadius: 104, options: []
        )
    }

    // MARK: Arrow
    // Reads as the comet's path continuing: fading dots, then a solid shaft.

    let arrowY = appSlot.y
    for (i, x) in [252.0, 240.0, 229.0].enumerated() {
        let r = 4.0 - CGFloat(i) * 1.1
        let c = p(x, arrowY)
        ctx.setFillColor(indigo.copy(alpha: 0.30 - CGFloat(i) * 0.09)!)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    let shaftStart: CGFloat = 268, shaftEnd: CGFloat = 366, headTip: CGFloat = 398
    let arrow = CGMutablePath()
    arrow.addRoundedRect(
        in: CGRect(x: shaftStart, y: H - arrowY - 7, width: shaftEnd - shaftStart, height: 14),
        cornerWidth: 7, cornerHeight: 7
    )
    arrow.move(to: p(shaftEnd - 4, arrowY - 24))
    arrow.addLine(to: p(headTip, arrowY))
    arrow.addLine(to: p(shaftEnd - 4, arrowY + 24))
    arrow.closeSubpath()

    ctx.saveGState()
    ctx.addPath(arrow)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([azure, indigo], [0, 1]),
        start: p(shaftStart, 0), end: p(headTip, 0), options: []
    )
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

// MARK: - Output

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
let resources = scriptDir.deletingLastPathComponent()

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let oneX = resources.appendingPathComponent("dmg-background.png")
let twoX = resources.appendingPathComponent("dmg-background@2x.png")
writePNG(render(scale: 1), to: oneX)
writePNG(render(scale: 2), to: twoX)

// Finder picks the right representation out of a multi-image TIFF, which is the
// only way to get a Retina-crisp DMG background.
let tiff = resources.appendingPathComponent("dmg-background.tiff")
let tiffutil = Process()
tiffutil.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
tiffutil.arguments = ["-cathidpicheck", oneX.path, twoX.path, "-out", tiff.path]
try! tiffutil.run()
tiffutil.waitUntilExit()
guard tiffutil.terminationStatus == 0 else { fatalError("tiffutil failed") }

print("""
✓ Wrote Resources/dmg-background.tiff (\(Int(W))×\(Int(H)), @1x + @2x)
  window \(Int(W))×\(Int(H)) · icon size \(Int(iconSize)) · \
app at (\(Int(appSlot.x)), \(Int(appSlot.y))) · \
Applications at (\(Int(applicationsSlot.x)), \(Int(applicationsSlot.y)))
""")
