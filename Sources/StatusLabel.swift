import AppKit

/// Draws the menu bar label as a single NSImage.
/// - Idle: a 14 pt ring whose pie fills clockwise with today / limit (template). Over the limit: solid system red.
/// - On a site: the site's logo plus the live session timer in monospaced digits. Over the limit: red.
enum StatusLabel {
    static let height: CGFloat = 18                      // fits 22–24 pt menu bars
    static let iconSide: CGFloat = 14
    static let gap: CGFloat = 4
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

    private static var bundledCache: [String: NSImage] = [:]
    private static var templateableCache: [String: Bool] = [:]

    // MARK: Idle ring

    static func ring(fraction: Double) -> NSImage {
        let over = fraction >= 1
        let size = NSSize(width: iconSide + 2, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            let d: CGFloat = 13
            let rect = NSRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d)
            if over {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
            NSColor.black.set()   // template: the system recolors black for the menu bar
            let outline = NSBezierPath(ovalIn: rect.insetBy(dx: 0.75, dy: 0.75))
            outline.lineWidth = 1.5
            outline.stroke()

            let f = max(0, min(1, fraction))
            if f > 0.001 {
                let center = NSPoint(x: rect.midX, y: rect.midY)
                let pie = NSBezierPath()
                pie.move(to: center)
                // Start at 12 o'clock and sweep clockwise.
                pie.appendArc(withCenter: center, radius: d / 2 - 2.6,
                              startAngle: 90, endAngle: 90 - 360 * CGFloat(f), clockwise: true)
                pie.close()
                pie.fill()
            }
            return true
        }
        image.isTemplate = !over
        return image
    }

    // MARK: Active site

    /// The logo to show for a site and whether it can be drawn as a template (monochrome) glyph.
    static func glyph(for site: SiteConfig, favicon: NSImage?) -> (image: NSImage, template: Bool)? {
        if let name = site.icon {
            if let cached = bundledCache[name] { return (cached, true) }
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                bundledCache[name] = img
                return (img, true)   // bundled glyphs are white-on-transparent: alpha works as a template
            }
        }
        if let favicon {
            let ok: Bool
            if let cached = templateableCache[site.id] { ok = cached } else {
                ok = hasTransparency(favicon)
                templateableCache[site.id] = ok
            }
            return (favicon, ok)
        }
        return nil
    }

    static func forgetFavicon(_ siteID: String) { templateableCache[siteID] = nil }

    static func active(glyph: (image: NSImage, template: Bool)?, text: String, over: Bool,
                       appearance: NSAppearance?) -> NSImage {
        // The whole image can be a template only if nothing in it needs its own color.
        let isTemplate = !over && (glyph == nil || glyph!.template)

        let textColor: NSColor
        if over {
            textColor = .systemRed
        } else if isTemplate {
            textColor = .black
        } else {
            // Full-color favicon: resolve the label color for the current menu bar appearance.
            var resolved = NSColor.labelColor
            if let appearance {
                appearance.performAsCurrentDrawingAppearance {
                    resolved = NSColor(cgColor: NSColor.labelColor.cgColor) ?? NSColor.labelColor
                }
            }
            textColor = resolved
        }

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let iconWidth: CGFloat = glyph == nil ? 0 : iconSide + gap
        let size = NSSize(width: ceil(iconWidth + textSize.width) + 1, height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            if let glyph {
                let r = NSRect(x: 0, y: (height - iconSide) / 2, width: iconSide, height: iconSide)
                if glyph.template {
                    tinted(glyph.image, over ? .systemRed : .black).draw(in: r)
                } else {
                    // Small full-color favicon, rounded like the popover tiles.
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).addClip()
                    glyph.image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            let y = (height - textSize.height) / 2
            (text as NSString).draw(at: NSPoint(x: iconWidth, y: y), withAttributes: attrs)
            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    // MARK: Helpers

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        let size = NSSize(width: iconSide * 2, height: iconSide * 2)
        return NSImage(size: size, flipped: false) { r in
            image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
    }

    // MARK: Pomodoro menu bar

    /// Idle menu bar mark. Template, so the system colors it with the menu bar.
    static func timerIcon() -> NSImage {
        let base = NSImage(systemSymbolName: "timer", accessibilityDescription: "Lapse")
            ?? NSImage(size: NSSize(width: 16, height: 16))
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = base.withSymbolConfiguration(config) ?? base
        image.isTemplate = true
        return image
    }

    /// Small status dot. Not a template: the countdown text stays the system menu bar color.
    static func statusDot(onBreak: Bool) -> NSImage {
        let size = NSSize(width: 16, height: 18)
        let color = onBreak
            ? NSColor(srgbRed: 52.0 / 255, green: 199.0 / 255, blue: 89.0 / 255, alpha: 1)
            : NSColor(srgbRed: 1, green: 90.0 / 255, blue: 54.0 / 255, alpha: 1)
        let image = NSImage(size: size, flipped: false) { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 4, y: 5, width: 8, height: 8)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// True when at least a quarter of the pixels are transparent, i.e. the logo has a shape
    /// that still reads as a silhouette. Opaque square favicons stay full color.
    private static func hasTransparency(_ image: NSImage) -> Bool {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let w = 32, h = 32
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        var clear = 0
        let drew: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return false }
        for i in stride(from: 3, to: buffer.count, by: 4) where buffer[i] < 26 { clear += 1 }
        return Double(clear) / Double(w * h) >= 0.25
    }
}
