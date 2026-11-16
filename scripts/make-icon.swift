// Regenerates Resources/AppIcon.icns:  swift scripts/make-icon.swift
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Hoopoe-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let size = CGFloat(pixels)

    // Standard macOS icon shape: a rounded square inset from the canvas.
    let inset = size * 0.1
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(
        starting: NSColor(srgbRed: 0.98, green: 0.66, blue: 0.30, alpha: 1),
        ending: NSColor(srgbRed: 0.84, green: 0.38, blue: 0.11, alpha: 1)
    )!.draw(in: shape, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: body.width * 0.5, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let bird = NSImage(systemSymbolName: "bird.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let origin = NSPoint(x: body.midX - bird.size.width / 2, y: body.midY - bird.size.height / 2)
        bird.draw(in: NSRect(origin: origin, size: bird.size))
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(output.path)")
