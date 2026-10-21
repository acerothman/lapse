import AppKit
import CoreGraphics
import UserNotifications

/// Something tracked in front right now. `browser` is set for sites.
struct Target: Equatable {
    let id: String
    let browser: String?
}

/// Polls the frontmost app every 2 s. If it is a supported browser, reads the active
/// tab URL via AppleScript and credits the elapsed time to the matching site.
final class Tracker {
    private let store: Store
    private var timer: Timer?
    private var lastTick = Date()
    private var lastSiteID: String?
    private var ticksSinceSave = 0
    private var scripts: [String: NSAppleScript] = [:]
    private var isAsleep = false
    private var carry: Double = 0                 // fractional seconds not yet credited

    // Current visit ("session") for the menu bar timer.
    private(set) var sessionSiteID: String?
    private(set) var sessionSeconds: Double = 0
    private var sessionLastSeen = Date.distantPast
    /// A visit continues if you come back to the same site within this many seconds.
    static let sessionGrace: TimeInterval = 30
    var onTick: (() -> Void)?
    /// Asked before time counts. Return false to hold the target (the pause screen is up).
    /// Called with nil when nothing tracked is in front.
    var gate: ((Target?) -> Bool)?

    /// bundle id -> AppleScript returning the active tab URL
    static let browsers: [String: String] = [
        "com.apple.Safari": safari("com.apple.Safari"),
        "com.apple.SafariTechnologyPreview": safari("com.apple.SafariTechnologyPreview"),
        "com.google.Chrome": chromium("com.google.Chrome"),
        "com.google.Chrome.beta": chromium("com.google.Chrome.beta"),
        "com.brave.Browser": chromium("com.brave.Browser"),
        "com.microsoft.edgemac": chromium("com.microsoft.edgemac"),
        "com.vivaldi.Vivaldi": chromium("com.vivaldi.Vivaldi"),
        "company.thebrowser.Browser": chromium("company.thebrowser.Browser"), // Arc
    ]
    private static func safari(_ id: String) -> String {
        #"tell application id "\#(id)" to return URL of front document"#
    }
    private static func chromium(_ id: String) -> String {
        #"tell application id "\#(id)" to return URL of active tab of front window"#
    }

    init(store: Store) {
        self.store = store
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.isAsleep = true }
        nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.isAsleep = true }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.wake() }
        nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.wake() }
    }

    private func wake() { isAsleep = false; lastTick = Date() }

    func start() {
        lastTick = Date()
        scheduleNext(after: 1)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 1 s while on a tracked site (live timer), 2 s otherwise (just watching for a site).
    private func scheduleNext(after interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = Date()
        // Cap elapsed time so sleep, a stalled AppleScript, or clock changes can't inflate totals.
        let elapsed = min(max(now.timeIntervalSince(lastTick), 0), 5)
        lastTick = now

        let idle = isAsleep || isIdle()
        if idle {
            // Going idle ends the visit.
            sessionSiteID = nil
            sessionSeconds = 0
        }
        var target = (idle || store.isPaused) ? nil : currentTarget()
        let watching = target != nil
        if let gate, !gate(target) { target = nil }
        let siteID = target?.id

        if let id = siteID {
            if id != lastSiteID { store.addVisit(to: id) }
            if id != sessionSiteID || now.timeIntervalSince(sessionLastSeen) > Self.sessionGrace {
                sessionSiteID = id
                sessionSeconds = 0
            }
            sessionSeconds += elapsed
            sessionLastSeen = now

            carry += elapsed
            let whole = Int(carry)
            if whole > 0 {
                carry -= Double(whole)
                store.add(seconds: whole, to: id)
            }
            checkLimit()
        } else {
            carry = 0
        }
        lastSiteID = siteID
        if store.currentSiteID != siteID { store.currentSiteID = siteID }
        let shown = siteID == nil ? 0 : Int(sessionSeconds)
        if store.sessionSeconds != shown { store.sessionSeconds = shown }

        ticksSinceSave += 1
        if ticksSinceSave >= 30 { ticksSinceSave = 0; store.save() }   // about 30 to 60 s
        onTick?()
        scheduleNext(after: watching ? 1 : 2)
    }

    private func isIdle() -> Bool {
        // kCGAnyInputEventType is ~0. The raw value is UInt32, so `~0` (Int) does not type-check.
        guard let anyInput = CGEventType(rawValue: ~UInt32(0)) else { return false }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return idle >= Double(store.settings.idleThresholdSeconds)
    }

    /// A tracked Mac app wins over a browser tab. Otherwise, a supported browser's active site.
    private func currentTarget() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bid = app.bundleIdentifier else { return nil }
        if store.app(for: bid) != nil {
            if let icon = app.icon { store.rememberIcon(icon, for: bid) }
            return Target(id: bid, browser: nil)
        }
        guard let source = Self.browsers[bid] else { return nil }
        guard let urlString = runScript(bid: bid, source: source),
              let url = URL(string: urlString),
              let site = store.site(for: url) else { return nil }
        return Target(id: site.id, browser: bid)
    }

    private func runScript(bid: String, source: String) -> String? {
        let script: NSAppleScript
        if let s = scripts[bid] { script = s } else {
            guard let s = NSAppleScript(source: source) else { return nil }
            scripts[bid] = s
            script = s
        }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if err != nil { return nil }   // no window, or Automation permission denied
        return result.stringValue
    }

    /// Closes the active tab in a supported browser. False if the browser refused or has no window.
    static func closeActiveTab(in bid: String) -> Bool {
        let source: String
        if bid.hasPrefix("com.apple.Safari") {
            source = #"tell application id "\#(bid)" to close current tab of front window"#
        } else if browsers[bid] != nil {
            source = #"tell application id "\#(bid)" to close active tab of front window"#
        } else {
            return false
        }
        guard let script = NSAppleScript(source: source) else { return false }
        var err: NSDictionary?
        _ = script.executeAndReturnError(&err)
        return err == nil
    }

    /// Runs the tab-URL script so macOS shows the Automation prompt for one browser.
    /// True when access was not refused. A missing window still counts as allowed.
    static func promptForBrowserAutomation() -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        let running = Set(apps.compactMap(\.bundleIdentifier))
        let bid: String
        if let front = apps.first(where: \.isActive)?.bundleIdentifier, browsers[front] != nil {
            bid = front
        } else if let any = browsers.keys.first(where: { running.contains($0) }) {
            bid = any
        } else {
            bid = "com.apple.Safari"
        }
        guard let source = browsers[bid], let script = NSAppleScript(source: source) else { return false }
        var err: NSDictionary?
        _ = script.executeAndReturnError(&err)
        guard let err else { return true }
        let number = err[NSAppleScript.errorNumber] as? Int
            ?? (err[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        // -1743 is errAEEventNotPermitted: the user chose not to allow control.
        return number != -1743
    }

    private func checkLimit() {
        guard store.settings.notificationsEnabled else { return }
        if store.isFocusHours(), store.focusMode == .block { return }
        let total = store.todayTotal, limit = store.overallLimitSeconds()
        guard limit > 0 else { return }
        let today = store.today
        if total >= limit, !today.notifiedLimit {
            store.markNotified(warning: false)
            notify(title: "Limit reached",
                   body: "That's your \(Fmt.long(limit)) for today.")
        } else if total >= limit * 8 / 10, total < limit, !today.notifiedWarning {
            store.markNotified(warning: true)
            notify(title: "\(Fmt.long(limit - total)) left today",
                   body: "You're at 80% of your \(Fmt.long(limit)) limit.")
        }
    }

    private func notify(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
