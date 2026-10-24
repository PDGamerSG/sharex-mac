import AppKit

// Original vector artwork rendered at each macOS app-icon size.
guard CommandLine.arguments.count == 2 else { fatalError("Pass an output .iconset directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = size * factor
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Icon context failed") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let scale = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        transform.concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 190, yRadius: 190)
        NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.35, blue: 0.72, alpha: 1),
                   ending: NSColor(calibratedRed: 0.05, green: 0.19, blue: 0.43, alpha: 1))!.draw(in: tile, angle: -90)
        NSColor.white.setStroke()
        let corners = NSBezierPath()
        corners.lineWidth = 52
        corners.lineCapStyle = .round
        corners.lineJoinStyle = .round
        for (x, y, dx, dy) in [(290.0, 730.0, 1.0, -1.0), (734, 730, -1, -1),
                               (290, 294, 1, 1), (734, 294, -1, 1)] {
            corners.move(to: NSPoint(x: x + dx * 112, y: y))
            corners.line(to: NSPoint(x: x, y: y))
            corners.line(to: NSPoint(x: x, y: y + dy * 112))
        }
        corners.stroke()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: 410, y: 456, width: 204, height: 112), xRadius: 18, yRadius: 18).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon encoding failed") }
        let suffix = factor == 2 ? "@2x" : ""
        try data.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
