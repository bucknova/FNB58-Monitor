import AppKit
// Draws the app icon: a measurement trace on a dark tile.
let out = CommandLine.arguments[1]
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let inset: CGFloat = 100
let tile = NSRect(x: inset, y: inset, width: 1024 - inset * 2, height: 1024 - inset * 2)
NSColor(srgbRed: 0.11, green: 0.118, blue: 0.13, alpha: 1).setFill()
NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()
NSColor(srgbRed: 0.19, green: 0.2, blue: 0.22, alpha: 1).setStroke()
for y in stride(from: 330.0, through: 700.0, by: 185.0) {
    let g = NSBezierPath(); g.move(to: NSPoint(x: 200, y: y)); g.line(to: NSPoint(x: 824, y: y)); g.lineWidth = 8; g.stroke()
}
let p = NSBezierPath()
p.move(to: NSPoint(x: 200, y: 400)); p.line(to: NSPoint(x: 350, y: 400)); p.line(to: NSPoint(x: 420, y: 680))
p.line(to: NSPoint(x: 500, y: 330)); p.line(to: NSPoint(x: 570, y: 620)); p.line(to: NSPoint(x: 824, y: 620))
p.lineWidth = 44; p.lineCapStyle = .round; p.lineJoinStyle = .round
NSColor(srgbRed: 0.353, green: 0.663, blue: 1, alpha: 1).setStroke(); p.stroke()
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
