import SwiftUI
import AppKit

/// Shared type, color and spacing. Monochrome on purpose: label colors for everything,
/// system red only when something is past its limit. Controls keep the system accent.
enum Theme {
    static let ink = Color.primary
    static let muted = Color.secondary
    static let faint = Color(nsColor: .tertiaryLabelColor)
    static let hairline = Color(nsColor: .separatorColor)
    static let track = Color.primary.opacity(0.08)
    static let tile = Color.primary.opacity(0.06)
    static let hover = Color.primary.opacity(0.06)
    static let over = Color(nsColor: .systemRed)

    static let gutter: CGFloat = 16

    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold).monospacedDigit()
    }
}

extension Color {
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

/// Small gray label above a group, in sentence case.
struct SectionLabel: View {
    let text: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
            Spacer(minLength: 8)
            if let trailing { Text(trailing).monospacedDigit() }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.muted)
    }
}

struct ProgressTrack: View {
    let fraction: Double
    var over: Bool = false
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(over ? Theme.over : Theme.ink)
                    .frame(width: max(fraction > 0 ? height : 0, min(1, max(0, fraction)) * g.size.width))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}

/// A short gray tag, like "Feed".
struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.tile))
    }
}

/// A keyboard hint, like the ones next to Raycast actions.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Theme.muted)
            .frame(minWidth: 16)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.tile))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

/// Text button with a hover fill, for toolbars and footers.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(configuration: configuration)
    }

    private struct QuietButtonBody: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabled ? Theme.ink : Theme.faint)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Theme.hover.opacity(2) : (hovering ? Theme.hover : .clear)))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// The site's logo as a monochrome glyph on a neutral tile. User-added sites keep their
/// own favicon on a white tile. Apps show their real icon.
struct ItemIcon: View {
    enum Source {
        case site(SiteConfig, favicon: NSImage?)
        case app(AppConfig, icon: NSImage?)
    }

    let source: Source
    var size: CGFloat = 22

    private static var glyphCache: [String: NSImage] = [:]

    static func bundledGlyph(_ name: String?) -> NSImage? {
        guard let name else { return nil }
        if let cached = glyphCache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        glyphCache[name] = image
        return image
    }

    var body: some View {
        let corner = size * 0.27
        Group {
            switch source {
            case .site(let site, let favicon):
                if let glyph = Self.bundledGlyph(site.icon) {
                    ZStack {
                        RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Theme.tile)
                        Image(nsImage: glyph)
                            .renderingMode(.template)
                            .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .foregroundStyle(Theme.ink)
                            .frame(width: size * 0.52, height: size * 0.52)
                    }
                } else if let favicon {
                    ZStack {
                        RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white)
                        Image(nsImage: favicon)
                            .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .frame(width: size * 0.68, height: size * 0.68)
                    }
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5))
                } else {
                    letter(site.name, corner: corner)
                }
            case .app(let app, let icon):
                if let icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: size * 1.12, height: size * 1.12)   // app icons carry their own margin
                } else {
                    letter(app.name, corner: corner)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private func letter(_ name: String, corner: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Theme.tile)
            Text(name.prefix(1).uppercased())
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
    }
}

/// The card that sits in the middle of the full-screen overlays.
struct OverlayCard<Content: View>: View {
    var width: CGFloat = 380
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(24)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 30, y: 12)
    }
}

extension Store {
    func iconSource(for id: String) -> ItemIcon.Source? {
        if let site = settings.sites.first(where: { $0.id == id }) { return .site(site, favicon: favicons[id]) }
        if let app = settings.apps.first(where: { $0.id == id }) { return .app(app, icon: appIcons[id]) }
        return nil
    }
}
