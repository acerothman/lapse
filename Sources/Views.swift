import SwiftUI
import Charts
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

extension Color {
    /// Focus sessions. The only non-semantic fill, used on the Start button and the focus dot.
    static let lapseAccent = Color(red: 1, green: 90.0 / 255, blue: 54.0 / 255)
    /// Breaks. System green, so a break never uses the focus accent.
    static let lapseBreak = Color(red: 52.0 / 255, green: 199.0 / 255, blue: 89.0 / 255)

    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

struct SiteIcon: View {
    let site: SiteConfig
    var favicon: NSImage? = nil   // fetched logo for user-added sites
    var size: CGFloat = 24

    private var bundled: NSImage? {
        guard let name = site.icon,
              let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        let corner = size * 0.25
        let glyph = bundled
        ZStack {
            if let glyph {
                // Built-in site: white logo on its brand color.
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color(hex: site.colorHex))
                Image(nsImage: glyph)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.54, height: size * 0.54)
            } else if let favicon {
                // User-added site: full-color favicon on a white tile, like an app icon.
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
                Image(nsImage: favicon)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.7, height: size * 0.7)
            } else {
                // Loading or failed: neutral letter tile.
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color(hex: "#8E8E93"))
                Text(site.name.prefix(1).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .controlBackgroundColor))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.2), value: favicon != nil)
    }
}

struct UsageBar: View {
    let fraction: Double
    var height: CGFloat = 3
    var color: Color = .primary

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}
