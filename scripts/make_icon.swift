// Renders a 1024x1024 app icon: the menu bar ring, two thirds full, in white on a graphite squircle.
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
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// A faint neutral falloff, darker at the bottom.
NSGradient(starting: NSColor(srgbRed: 0.19, green: 0.19, blue: 0.20, alpha: 1),
           ending: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1))?
    .draw(in: shape, angle: -90)

// Thin light edge along the top, like machined metal.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
let edge = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
edge.lineWidth = 3
NSColor.white.withAlphaComponent(0.07).setStroke()
edge.stroke()
NSGraphicsContext.restoreGraphicsState()

// The ring, with the same proportions as the 13 pt menu bar glyph.
let center = NSPoint(x: 512, y: 512)
let outer: CGFloat = 250
let band = outer * 0.23
let ring = NSBezierPath()
ring.appendArc(withCenter: center, radius: outer - band / 2, startAngle: 0, endAngle: 360)
ring.lineWidth = band
NSColor.white.setStroke()
ring.stroke()

let fraction: CGFloat = 0.68
let pie = NSBezierPath()
pie.move(to: center)
pie.appendArc(withCenter: center, radius: outer * 0.6, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
pie.close()
NSColor.white.setFill()
pie.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
