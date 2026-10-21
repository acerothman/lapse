import AppKit
import SwiftUI

/// README screenshots of the real app, with made-up data. scripts/screenshots.sh launches
/// the app with LAPSE_SCENE set, waits for the window number in LAPSE_SCENE_OUT, and
/// captures that window. Scenes only run with LAPSE_DATA_DIR set, so real data is never touched.
@MainActor
enum Scenes {
    private static let env = ProcessInfo.processInfo.environment

    static var current: String? {
        guard let scene = env["LAPSE_SCENE"], !scene.isEmpty,
              let dir = env["LAPSE_DATA_DIR"], !dir.isEmpty else { return nil }
        return scene
    }

    static func applyAppearance() {
        switch env["LAPSE_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
    }

    private static var keep: [AnyObject] = []

    static func run(_ app: AppDelegate) {
        guard let scene = current else { return }
        DemoData.load(into: app.store)
        app.updateLabel(force: true)

        switch scene {
        case "popover":
            app.store.currentSiteID = "x.com"
            app.store.sessionSeconds = 252
            app.popover.appearance = NSApp.appearance
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                app.showPopover()
                // The popover's material only looks right composited over what's behind it,
                // so capture the screen region (popover on the backdrop) instead of the window.
                let window = app.popover.contentViewController?.view.window
                if let region = backdrop(behind: window) { report(region: region) }
            }
        case "settings-general", "settings-tracking", "settings-focus", "settings-log":
            let tabs = ["settings-general", "settings-tracking", "settings-focus", "settings-log"]
            app.showSettings(tab: tabs.firstIndex(of: scene) ?? 0)
            report(app.settingsController?.window)
        case let s where s.hasPrefix("onboarding-"):
            app.showOnboarding(step: Int(s.dropFirst("onboarding-".count)) ?? 0)
            report(app.onboardingWindow)
        case "friction-countdown", "friction-reason":
            let model = FrictionModel()
            model.target = Target(id: "x.com", browser: "com.apple.Safari")
            model.name = "X"
            model.icon = app.store.iconSource(for: "x.com")
            if scene == "friction-reason" {
                model.kind = .reason
                model.name = "Instagram"
                model.icon = app.store.iconSource(for: "instagram.com")
                model.reason = "Replying to Maya about Friday"
                model.lastReason = "Posting the race photos"
            } else {
                model.kind = .countdown
                model.total = 10
                model.remaining = 7
            }
            showCard(FrictionCard(model: model, open: {}, backOut: {}))
        case "softblock":
            let model = SoftBlockModel()
            model.name = "YouTube"
            model.icon = app.store.iconSource(for: "youtube.com")
            model.usedToday = 47 * 60
            model.reason = .item(name: "YouTube", used: 47 * 60, limit: 45 * 60)
            showCard(SoftBlockCard(model: model, snooze5: {}, snooze15: {}, turnOff: {}))
        case "idle":
            // Stays running with demo data, for trying lapse:// links.
            break
        case "menubar":
            renderMenuBar(app.store)
            NSApp.terminate(nil)
        default:
            NSApp.terminate(nil)
        }
    }

    /// Writes the window number once the window has settled.
    private static func report(_ window: NSWindow?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard let window, let out = env["LAPSE_SCENE_OUT"] else { return }
            try? "\(window.windowNumber)".write(toFile: out, atomically: true, encoding: .utf8)
        }
    }

    /// A plain desktop-colored window behind the popover, so its translucent material
    /// shows a neutral backdrop instead of whatever is on screen.
    @discardableResult
    private static func backdrop(behind popover: NSWindow?) -> NSRect? {
        guard let popover else { return nil }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var frame = popover.frame.insetBy(dx: -48, dy: -48)
        frame.size.height -= 48   // stop at the top of the popover, below the menu bar
        let w = NSWindow(contentRect: frame, styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.backgroundColor = dark ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                                 : NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
        w.level = popover.level
        w.order(.below, relativeTo: popover.windowNumber)
        keep.append(w)
        return frame
    }

    /// Writes a screen region as "R:x,y,w,h" in screencapture's top-left coordinates.
    private static func report(region: NSRect) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard let out = env["LAPSE_SCENE_OUT"], let main = NSScreen.screens.first else { return }
            let top = main.frame.maxY - region.maxY
            let text = "R:\(Int(region.minX)),\(Int(top)),\(Int(region.width)),\(Int(region.height))"
            try? text.write(toFile: out, atomically: true, encoding: .utf8)
        }
    }

    /// Hosts an overlay card on its own, with room for its shadow.
    private static func showCard<V: View>(_ card: V) {
        let host = NSHostingController(rootView: card.padding(56))
        host.sizingOptions = [.preferredContentSize]
        let size = host.view.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentViewController = host
        panel.setContentSize(size)
        panel.center()
        panel.orderFrontRegardless()
        keep.append(panel)
        report(panel)
    }

    /// The real menu bar label drawings on a plain menu bar strip, light and dark.
    private static func renderMenuBar(_ store: Store) {
        guard let dir = env["LAPSE_SCENE_OUT"].map({ URL(fileURLWithPath: $0).deletingLastPathComponent() }) else { return }
        let x = store.settings.sites.first(where: { $0.id == "x.com" })!
        let glyph = StatusLabel.glyph(for: x, favicon: nil)
        let states: [(String, NSImage)] = [
            ("ring", StatusLabel.ring(fraction: 0.62)),
            ("timer", StatusLabel.active(glyph: glyph, text: "4:12", over: false, appearance: nil)),
            ("over", StatusLabel.active(glyph: glyph, text: "1:02:09", over: true, appearance: nil)),
            ("paused", StatusLabel.paused()),
        ]
        for (name, label) in states {
            for dark in [false, true] {
                let png = strip(label: label, dark: dark)
                try? png?.write(to: dir.appendingPathComponent("menubar-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    private static func strip(label: NSImage, dark: Bool) -> Data? {
        let scale: CGFloat = 2
        let size = NSSize(width: 300, height: 30)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let bg = dark ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.14, alpha: 1) : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)
        let fg = dark ? NSColor.white : NSColor(srgbRed: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        bg.setFill()
        NSRect(origin: .zero, size: size).fill()

        let clock = "Tue 9:41 PM" as NSString
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
        let clockSize = clock.size(withAttributes: attrs)
        clock.draw(at: NSPoint(x: size.width - clockSize.width - 14, y: (size.height - clockSize.height) / 2), withAttributes: attrs)

        let labelSize = label.size
        let x = size.width - clockSize.width - 14 - 22 - labelSize.width
        let rect = NSRect(x: x, y: (size.height - labelSize.height) / 2, width: labelSize.width, height: labelSize.height)
        if label.isTemplate {
            let tinted = NSImage(size: labelSize, flipped: false) { r in
                label.draw(in: r)
                fg.set()
                r.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: rect)
        } else {
            label.draw(in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

/// A believable week for screenshots.
enum DemoData {
    @MainActor
    static func load(into store: Store) {
        var settings = AppSettings()
        settings.didFinishOnboarding = true
        settings.dailyLimitMinutes = 90
        settings.focus.enabled = true
        settings.focus.mode = .stricter
        settings.focus.dailyLimitMinutes = 30
        for i in settings.sites.indices {
            switch settings.sites[i].id {
            case "x.com":
                settings.sites[i].friction = FrictionSettings(kind: .countdown, seconds: 10, trigger: .always)
            case "instagram.com":
                settings.sites[i].friction = FrictionSettings(kind: .reason, seconds: 10, trigger: .always)
            case "youtube.com":
                settings.sites[i].dailyLimitMinutes = 45
                settings.sites[i].feedOnly = true
            case "reddit.com":
                settings.sites[i].feedOnly = true
            default:
                break
            }
        }
        if let i = settings.apps.firstIndex(where: { $0.id == "com.hnc.Discord" }) {
            settings.apps[i].enabled = true
            settings.apps[i].dailyLimitMinutes = 30
        }

        // Minutes per day, oldest first. Today is last.
        let plan: [[String: Int]] = [
            ["x.com": 28, "youtube.com": 18, "reddit.com": 9, "instagram.com": 7],
            ["x.com": 41, "youtube.com": 26, "reddit.com": 12, "instagram.com": 9],
            ["x.com": 19, "youtube.com": 15, "reddit.com": 8, "instagram.com": 5],
            ["x.com": 52, "youtube.com": 31, "reddit.com": 14, "instagram.com": 7, "com.hnc.Discord": 6],
            ["x.com": 33, "youtube.com": 21, "reddit.com": 11, "instagram.com": 6],
            ["x.com": 17, "youtube.com": 12, "reddit.com": 6, "instagram.com": 4],
            ["x.com": 34, "youtube.com": 22, "reddit.com": 9, "instagram.com": 6, "com.hnc.Discord": 4],
        ]
        let visits = ["x.com": 14, "youtube.com": 3, "reddit.com": 6, "instagram.com": 4, "com.hnc.Discord": 2]
        let cal = Calendar.current
        var days: [String: DayRecord] = [:]
        for (offset, minutes) in plan.reversed().enumerated() {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            var rec = DayRecord()
            for (id, m) in minutes { rec.seconds[id] = m * 60 + (offset == 0 ? 17 : 0) }
            rec.visits = visits
            days[DayKey.key(date)] = rec
        }

        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let log = [
            FrictionEntry(date: at(1, 13, 15), itemID: "x.com", name: "X", kind: .countdown, reason: nil, opened: false),
            FrictionEntry(date: at(1, 16, 2), itemID: "reddit.com", name: "Reddit", kind: .reason,
                          reason: "Looking up why the dishwasher beeps", opened: true),
            FrictionEntry(date: at(1, 18, 20), itemID: "instagram.com", name: "Instagram", kind: .reason,
                          reason: "Posting the race photos", opened: true),
            FrictionEntry(date: at(0, 9, 41), itemID: "x.com", name: "X", kind: .countdown, reason: nil, opened: true),
            FrictionEntry(date: at(0, 11, 12), itemID: "instagram.com", name: "Instagram", kind: .reason,
                          reason: "Replying to Maya about Friday", opened: true),
            FrictionEntry(date: at(0, 14, 3), itemID: "x.com", name: "X", kind: .countdown, reason: nil, opened: false),
            FrictionEntry(date: at(0, 15, 37), itemID: "instagram.com", name: "Instagram", kind: .reason,
                          reason: "Nothing really", opened: false),
        ]
        store.replaceAll(settings: settings, days: days, log: log, state: RuntimeState())
    }
}
