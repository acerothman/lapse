// Renders a 1024x1024 app icon: SF Symbol hourglass on a system-blue squircle.
// Usage: swift scripts/make_icon.swift out.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let px = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
rep.size = NSSize(width: px, height: px)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple icon grid: 824pt body inset 100pt, ~185pt corner radius
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Subtle top-to-bottom light, like Apple's own icons
NSGradient(starting: NSColor(srgbRed: 0.30, green: 0.64, blue: 1.0, alpha: 1),
           ending: NSColor(srgbRed: 0.0, green: 0.40, blue: 0.92, alpha: 1))?
    .draw(in: shape, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let sym = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = sym.size
    sym.draw(in: NSRect(x: (Double(px) - s.width) / 2, y: (Double(px) - s.height) / 2,
                        width: s.width, height: s.height))
}
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
