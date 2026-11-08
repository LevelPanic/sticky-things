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
    // The whole icon is the sticky note: warm paper (no purple, no glow).
    NSGradient(colors: [color(0xFFF1A8), color(0xFFE279), color(0xF8CF55)], atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: -70)

    // Handwriting lines in ink.
    color(0x6C4F25, 0.42).setFill()
    for (i, width) in [CGFloat(430), 520, 330].enumerated() {
        let y = 640 - CGFloat(i) * 92
        NSBezierPath(roundedRect: NSRect(x: 230, y: y, width: width, height: 38), xRadius: 19, yRadius: 19).fill()
    }

    // The bottom-right corner peels up: cut the corner away…
    let f: CGFloat = 300
    let cut = NSBezierPath()
    cut.move(to: NSPoint(x: body.maxX - f, y: body.minY - 40))
    cut.line(to: NSPoint(x: body.maxX + 40, y: body.minY + f))
    cut.line(to: NSPoint(x: body.maxX + 40, y: body.minY - 40))
    cut.close()
    NSGraphicsContext.current?.compositingOperation = .clear
    cut.fill()
    NSGraphicsContext.current?.compositingOperation = .sourceOver

    // …and fold it back over the note.
    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: body.maxX - f, y: body.minY))
    flap.line(to: NSPoint(x: body.maxX, y: body.minY + f))
    flap.curve(to: NSPoint(x: body.maxX - f * 0.92, y: body.minY + f * 0.92),
               controlPoint1: NSPoint(x: body.maxX - f * 0.4, y: body.minY + f * 1.02),
               controlPoint2: NSPoint(x: body.maxX - f * 0.75, y: body.minY + f * 0.98))
    flap.close()
    NSGraphicsContext.saveGraphicsState()
    let flapShadow = NSShadow()
    flapShadow.shadowColor = color(0x47300C, 0.35)
    flapShadow.shadowBlurRadius = 26
    flapShadow.shadowOffset = NSSize(width: -10, height: 12)
    flapShadow.set()
    color(0xFFF6CF).setFill()
    flap.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    flap.addClip()
    NSGradient(colors: [color(0xFFFBE8), color(0xFFE48A)])!.draw(in: NSRect(x: body.maxX - f, y: body.minY, width: f, height: f), angle: 45)
    NSGraphicsContext.restoreGraphicsState()

    // Thin inner edge so the paper reads on light backgrounds.
    color(0x47300C, 0.12).setStroke()
    squircle.lineWidth = 3
    squircle.stroke()
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
