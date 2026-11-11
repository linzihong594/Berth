import AppKit

// Editable vector artwork. The open ivory berth holds a single amber boat.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()

    let tile = NSBezierPath(roundedRect: NSRect(x: 84, y: 84, width: 856, height: 856), xRadius: 191, yRadius: 191)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(0x062E36, alpha: 0.28)
    tileShadow.shadowBlurRadius = 24
    tileShadow.shadowOffset = NSSize(width: 0, height: -12)
    tileShadow.set()
    color(0x0B525B).setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x083D49), color(0x10737A), color(0x42A79E)])!.draw(in: tile, angle: 75)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let glow = NSBezierPath(ovalIn: NSRect(x: 54, y: 605, width: 880, height: 500))
    NSGradient(starting: color(0xC4FFF0, alpha: 0.15), ending: color(0xC4FFF0, alpha: 0))!.draw(in: glow, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, alpha: 0.21).setStroke(); tile.lineWidth = 2; tile.stroke()

    let halo = NSBezierPath(ovalIn: NSRect(x: 208, y: 202, width: 608, height: 608))
    color(0xD9FFF5, alpha: 0.09).setStroke(); halo.lineWidth = 3; halo.stroke()

    let berth = NSBezierPath()
    berth.move(to: NSPoint(x: 322, y: 654))
    berth.line(to: NSPoint(x: 322, y: 434))
    berth.curve(to: NSPoint(x: 512, y: 278), controlPoint1: NSPoint(x: 322, y: 323), controlPoint2: NSPoint(x: 395, y: 278))
    berth.curve(to: NSPoint(x: 702, y: 434), controlPoint1: NSPoint(x: 629, y: 278), controlPoint2: NSPoint(x: 702, y: 323))
    berth.line(to: NSPoint(x: 702, y: 654))
    berth.lineWidth = 88; berth.lineCapStyle = .round; berth.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let markShadow = NSShadow()
    markShadow.shadowColor = color(0x002832, alpha: 0.28)
    markShadow.shadowBlurRadius = 18; markShadow.shadowOffset = NSSize(width: 0, height: -12); markShadow.set()
    color(0xF6F8ED).setStroke(); berth.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let boat = NSBezierPath()
    boat.move(to: NSPoint(x: 512, y: 749))
    boat.curve(to: NSPoint(x: 456, y: 507), controlPoint1: NSPoint(x: 457, y: 698), controlPoint2: NSPoint(x: 437, y: 562))
    boat.curve(to: NSPoint(x: 568, y: 507), controlPoint1: NSPoint(x: 470, y: 466), controlPoint2: NSPoint(x: 554, y: 466))
    boat.curve(to: NSPoint(x: 512, y: 749), controlPoint1: NSPoint(x: 587, y: 562), controlPoint2: NSPoint(x: 567, y: 698))
    boat.close()
    NSGraphicsContext.saveGraphicsState()
    let boatShadow = NSShadow()
    boatShadow.shadowColor = color(0x002F36, alpha: 0.35)
    boatShadow.shadowBlurRadius = 16; boatShadow.shadowOffset = NSSize(width: 0, height: -10); boatShadow.set()
    color(0xF6C768).setFill(); boat.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0xE7AD50), color(0xFFE4A3)])!.draw(in: boat, angle: 90)
    let cabin = NSBezierPath(roundedRect: NSRect(x: 499, y: 544, width: 26, height: 101), xRadius: 13, yRadius: 13)
    color(0xFFFBEB, alpha: 0.86).setFill(); cabin.fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
if CommandLine.arguments.count > 2 {
    try render(512).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
