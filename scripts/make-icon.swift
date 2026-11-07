#!/usr/bin/env swift
// Draws the Sticky Things app icon and writes an .icns file.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let px = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / 1024, y: size / 1024)

    // macOS icon grid: 824pt body centred on a 1024 canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    // Drop shadow under the whole icon.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x4B57D6).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [color(0x5B7CF6), color(0x6A4FE0), color(0x8E3FC9)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!.draw(in: body, angle: -60)
    // Soft light from the top-left.
    NSGradient(colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)])!
        .draw(fromCenter: NSPoint(x: 260, y: 860), radius: 0, toCenter: NSPoint(x: 260, y: 860), radius: 620, options: [])

    // The sticky note, tucked into the bottom-right corner.
    let s: CGFloat = 610
    let f: CGFloat = s * 0.24
    ctx.saveGState()
    ctx.translateBy(x: 668, y: 372)
    ctx.rotate(by: 11 * .pi / 180)

    let note = NSBezierPath()
    note.move(to: NSPoint(x: -s / 2 + f, y: s / 2))
    note.line(to: NSPoint(x: s / 2 - 30, y: s / 2))
    note.curve(to: NSPoint(x: s / 2, y: s / 2 - 30), controlPoint1: NSPoint(x: s / 2, y: s / 2), controlPoint2: NSPoint(x: s / 2, y: s / 2))
    note.line(to: NSPoint(x: s / 2, y: -s / 2))
    note.line(to: NSPoint(x: -s / 2, y: -s / 2))
    note.line(to: NSPoint(x: -s / 2, y: s / 2 - f))
    note.close()

    NSGraphicsContext.saveGraphicsState()
    let noteShadow = NSShadow()
    noteShadow.shadowColor = color(0x1A0B4A, 0.45)
    noteShadow.shadowBlurRadius = 46
    noteShadow.shadowOffset = NSSize(width: -10, height: 18)
    noteShadow.set()
    color(0xFFD84A).setFill()
    note.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    note.addClip()
    NSGradient(colors: [color(0xFFEA8A), color(0xFFD23F), color(0xFFC21F)], atLocations: [0, 0.6, 1], colorSpace: .sRGB)!
        .draw(in: NSRect(x: -s / 2, y: -s / 2, width: s, height: s), angle: -70)
    // Handwriting lines.
    color(0x9A6A00, 0.32).setFill()
    for (i, width) in [CGFloat(300), 380, 230].enumerated() {
        let y = s / 2 - f - 70 - CGFloat(i) * 74
        NSBezierPath(roundedRect: NSRect(x: -s / 2 + 92, y: y, width: width, height: 30), xRadius: 15, yRadius: 15).fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // The dog-ear flap.
    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: -s / 2 + f, y: s / 2))
    flap.line(to: NSPoint(x: -s / 2, y: s / 2 - f))
    flap.curve(to: NSPoint(x: -s / 2 + f, y: s / 2 - f),
               controlPoint1: NSPoint(x: -s / 2 + f * 0.45, y: s / 2 - f * 1.04),
               controlPoint2: NSPoint(x: -s / 2 + f * 0.8, y: s / 2 - f))
    flap.curve(to: NSPoint(x: -s / 2 + f, y: s / 2),
               controlPoint1: NSPoint(x: -s / 2 + f, y: s / 2 - f * 0.8),
               controlPoint2: NSPoint(x: -s / 2 + f * 1.04, y: s / 2 - f * 0.45))
    flap.close()
    NSGraphicsContext.saveGraphicsState()
    let flapShadow = NSShadow()
    flapShadow.shadowColor = color(0x6B4A00, 0.4)
    flapShadow.shadowBlurRadius = 16
    flapShadow.shadowOffset = NSSize(width: 6, height: -8)
    flapShadow.set()
    color(0xFFF4C2).setFill()
    flap.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    flap.addClip()
    NSGradient(colors: [color(0xFFFBE6), color(0xFFE27A)])!
        .draw(in: NSRect(x: -s / 2, y: s / 2 - f, width: f, height: f), angle: -45)
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()

    // Thin inner edge highlight.
    color(0xFFFFFF, 0.18).setStroke()
    squircle.lineWidth = 3
    squircle.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let rep = drawIcon(size: CGFloat(base * scale))
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
// Also keep a large PNG next to the .icns for the README.
let preview = URL(fileURLWithPath: output).deletingPathExtension().appendingPathExtension("png")
try drawIcon(size: 1024).representation(using: .png, properties: [:])!.write(to: preview)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote \(output)" : "iconutil failed")
