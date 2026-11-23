// Draws the Nirvana Wheel app icon: a dark rounded square with a ring of eight segments, one lit in yellow.
// Usage: swift scripts/make_icon.swift <out-dir>   (writes AppIcon.icns there)
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.09
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(colors: [NSColor(calibratedWhite: 0.16, alpha: 1), NSColor(calibratedWhite: 0.05, alpha: 1)])!
        .draw(in: bg, angle: -90)
    let c = NSPoint(x: s / 2, y: s / 2)
    let outer = tile.width * 0.36, inner = tile.width * 0.17
    let n = 8
    for i in 0..<n {
        let slice = 360.0 / Double(n)
        // AppKit angles: 0° = 3 o'clock, counter-clockwise. Item 0 centred on 12 o'clock.
        let mid = 90.0 - slice * Double(i)
        let a0 = CGFloat(mid - slice / 2 + 2.2), a1 = CGFloat(mid + slice / 2 - 2.2)
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: outer, startAngle: a0, endAngle: a1)
        p.appendArc(withCenter: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.close()
        (i == 1 ? NSColor(calibratedRed: 1, green: 0.847, blue: 0.302, alpha: 1)
                : NSColor(calibratedWhite: 1, alpha: 0.16)).setFill()
        p.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "AppIcon.icns written" : "iconutil failed")
