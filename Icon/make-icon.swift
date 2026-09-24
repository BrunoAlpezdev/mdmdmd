// Renders the app icon: a Big Sur squircle with a purple-to-pink gradient,
// "md" in SF Rounded Black and a chunky down arrow, the Markdown mark's nod.
// Usage: swift Icon/make-icon.swift <output-dir>   (writes an .iconset folder)
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024  // design at 1024, scale everything

    // Squircle with the standard icon-grid margin and a soft shadow.
    let rect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: 186 * s, yRadius: 186 * s)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * s), blur: 44 * s, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    NSColor.white.setFill()
    squircle.fill()
    ctx.restoreGState()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.31, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.72, green: 0.34, blue: 0.96, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.42, blue: 0.62, alpha: 1),
    ])!
    gradient.draw(in: squircle, angle: -55)

    // A faint highlight on the top edge so it reads as a physical tile.
    ctx.saveGState()
    squircle.addClip()
    let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
    sheen.draw(in: NSRect(x: rect.minX, y: rect.maxY - 300 * s, width: rect.width, height: 300 * s), angle: -90)
    ctx.restoreGState()

    // "md"
    let descriptor = NSFont.systemFont(ofSize: 430 * s, weight: .black).fontDescriptor.withDesign(.rounded)!
    let font = NSFont(descriptor: descriptor, size: 430 * s)!
    let text = NSAttributedString(string: "md", attributes: [
        .font: font, .foregroundColor: NSColor.white, .kern: -24 * s,
    ])
    let textSize = text.size()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 18 * s, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    text.draw(at: NSPoint(x: (size - textSize.width) / 2, y: 405 * s))
    ctx.restoreGState()

    // Down arrow, the Markdown mark's other half, drawn as a rounded stroke.
    let arrow = NSBezierPath()
    arrow.lineWidth = 64 * s
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 512 * s, y: 372 * s))
    arrow.line(to: NSPoint(x: 512 * s, y: 218 * s))
    arrow.move(to: NSPoint(x: 424 * s, y: 300 * s))
    arrow.line(to: NSPoint(x: 512 * s, y: 212 * s))
    arrow.line(to: NSPoint(x: 600 * s, y: 300 * s))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 18 * s, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    NSColor.white.setStroke()
    arrow.stroke()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

func write(_ image: NSImage, pixels: Int, name: String) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

for points in [16, 32, 128, 256, 512] {
    try write(render(CGFloat(points)), pixels: points, name: "icon_\(points)x\(points).png")
    try write(render(CGFloat(points * 2)), pixels: points * 2, name: "icon_\(points)x\(points)@2x.png")
}
