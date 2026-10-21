import Foundation
import Combine
import AppKit

final class Store: ObservableObject {
    /// One store per process. The app delegate and App Intents both use it.
    static let shared = Store()

    @Published var settings: AppSettings { didSet { save() } }
    @Published private(set) var days: [String: DayRecord]
    @Published var currentSiteID: String?
    /// Seconds in the current visit, for the popover. Set by the tracker.
    @Published var sessionSeconds: Int = 0
    /// Fetched logos for user-added sites, keyed by site id (domain).
    @Published private(set) var favicons: [String: NSImage] = [:]
    /// App icons from NSWorkspace, keyed by bundle id.
    @Published private(set) var appIcons: [String: NSImage] = [:]
    /// Pause screens and what happened after each, newest last.
    @Published private(set) var log: [FrictionEntry]
    @Published private(set) var state: RuntimeState
    private var faviconFetchesInFlight = Set<String>()

    private let fileURL: URL

    /// ~/Library/Application Support/Lapse, or LAPSE_DATA_DIR when set (used for screenshots).
    static let dataDirectory: URL = {
        if let custom = ProcessInfo.processInfo.environment["LAPSE_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lapse", isDirectory: true)
    }()

    init() {
        let dir = Self.dataDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")

        if let data = try? Data(contentsOf: fileURL),
           let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            settings = p.settings
            days = p.days
            log = p.log ?? []
            state = p.state ?? RuntimeState()
        } else {
            settings = AppSettings()
            days = [:]
            log = []
            state = RuntimeState()
        }
    }

    // MARK: Queries
    var todayKey: String { DayKey.key() }
    var today: DayRecord { days[todayKey] ?? DayRecord() }
    var todayTotal: Int { today.total }
    /// The limit the menu bar ring uses. During focus hours this is the focus limit.
    var limitSeconds: Int { overallLimitSeconds() }
    var enabledSites: [SiteConfig] { settings.sites.filter(\.enabled) }
    var enabledApps: [AppConfig] { settings.apps.filter(\.enabled) }

    func site(for host: String) -> SiteConfig? {
        enabledSites.first { $0.matches(host: host) }
    }

    /// The site this address counts for, if any. Feed-only sites count only on their feed.
    func site(for url: URL) -> SiteConfig? {
        guard let host = url.host, let site = site(for: host) else { return nil }
        if site.countsFeedOnly && !FeedRules.isFeed(siteID: site.id, url: url) { return nil }
        return site
    }

    func app(for bundleID: String) -> AppConfig? {
        enabledApps.first { $0.id == bundleID }
    }

    func displayName(for id: String) -> String {
        if let site = settings.sites.first(where: { $0.id == id }) { return site.name }
        if let app = settings.apps.first(where: { $0.id == id }) { return app.name }
        return id
    }

    func seconds(for id: String) -> Int { today.seconds[id] ?? 0 }

    // MARK: Pause

    var isPaused: Bool { (state.pausedUntil ?? .distantPast) > Date() }
    /// Nil when not paused. Date.distantFuture means until resumed.
    var pausedUntil: Date? { isPaused ? state.pausedUntil : nil }

    /// Nil pauses until resumed.
    func pause(until date: Date?) {
        state.pausedUntil = date ?? .distantFuture
        save()
    }

    func pause(minutes: Int?) {
        pause(until: minutes.map { Date().addingTimeInterval(TimeInterval($0 * 60)) })
    }

    func pauseUntilTomorrow() {
        let start = Calendar.current.startOfDay(for: Date())
        pause(until: Calendar.current.date(byAdding: .day, value: 1, to: start))
    }

    func resume() {
        state.pausedUntil = nil
        save()
    }

    // MARK: Focus and limits

    enum FocusSource { case manual, filter, schedule }

    /// The schedule from Settings, ignoring Shortcuts and Focus filters.
    func scheduleSaysFocus(at date: Date = Date()) -> Bool {
        let focus = settings.focus
        guard focus.enabled else { return false }
        let cal = Calendar.current
        let index = cal.component(.weekday, from: date) - 1 // 1 = Sunday
        let minutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let start = focus.startMinutes
        let end = focus.endMinutes
        let dayOn = { (i: Int) -> Bool in focus.days.indices.contains(i) && focus.days[i] }
        if start == end { return dayOn(index) }
        if start < end { return dayOn(index) && minutes >= start && minutes < end }
        // Overnight window: the part after midnight belongs to the day it started.
        if minutes >= start { return dayOn(index) }
        if minutes < end { return dayOn((index + 6) % 7) }
        return false
    }

    private func liveOverride(at date: Date = Date()) -> FocusOverride? {
        guard let o = state.focusOverride else { return nil }
        if let until = o.until, until <= date { return nil }
        return o
    }

    func isFocusHours(at date: Date = Date()) -> Bool {
        if let o = liveOverride(at: date) { return o.on }
        if state.focusFilter != nil { return true }
        return scheduleSaysFocus(at: date)
    }

    /// Why focus hours are on right now, if they are.
    var focusSource: FocusSource? {
        if let o = liveOverride() { return o.on ? .manual : nil }
        if state.focusFilter != nil { return .filter }
        return scheduleSaysFocus() ? .schedule : nil
    }

    /// Stricter or block, for whatever turned focus hours on.
    var focusMode: FocusMode {
        if liveOverride()?.on != true, let mode = state.focusFilter { return mode }
        return settings.focus.mode
    }

    /// When focus hours end, if Lapse can know.
    func focusEnds() -> Date? {
        switch focusSource {
        case .manual: return liveOverride()?.until
        case .filter, .none: return nil
        case .schedule: return scheduleEnd(after: Date())
        }
    }

    /// First minute after `date` when the schedule is off. Nil if it never is in the next week.
    private func scheduleEnd(after date: Date) -> Date? {
        let cal = Calendar.current
        var t = cal.date(bySetting: .second, value: 0, of: date) ?? date
        for _ in 0..<(7 * 24 * 60) {
            t = t.addingTimeInterval(60)
            if !scheduleSaysFocus(at: t) { return t }
        }
        return nil
    }

    /// Nil runs until stopped.
    func startFocus(minutes: Int?) {
        let until = minutes.map { Date().addingTimeInterval(TimeInterval(max(1, $0) * 60)) }
        state.focusOverride = FocusOverride(on: true, until: until)
        save()
    }

    func stopFocus() {
        if state.focusFilter != nil {
            // Stays off until that Focus ends.
            state.focusOverride = FocusOverride(on: false, until: nil)
        } else if scheduleSaysFocus() {
            state.focusOverride = FocusOverride(on: false, until: scheduleEnd(after: Date()))
        } else {
            state.focusOverride = nil
        }
        save()
    }

    /// Called by the Focus filter. Nil when that Focus turns off.
    func applyFocusFilter(_ mode: FocusMode?) {
        state.focusFilter = mode
        if mode != nil {
            // A Focus turning on wins over an earlier manual stop.
            if state.focusOverride?.on == false { state.focusOverride = nil }
        } else if let o = state.focusOverride, !o.on, o.until == nil {
            state.focusOverride = nil
        }
        save()
    }

    /// Overall cap in seconds for right now. Zero means block as soon as a tracked site or app is in front.
    func overallLimitSeconds(at date: Date = Date()) -> Int {
        if isFocusHours(at: date) {
            if focusMode == .block { return 0 }
            return max(0, settings.focus.dailyLimitMinutes) * 60
        }
        return max(0, settings.dailyLimitMinutes) * 60
    }

    /// Per-site or per-app cap in seconds, if one is set. Nil means only the overall limit applies.
    func itemLimitSeconds(for id: String, at date: Date = Date()) -> Int? {
        let focusOn = isFocusHours(at: date)
        if focusOn && focusMode == .block { return 0 }
        let daily: Int?
        let focus: Int?
        if let site = settings.sites.first(where: { $0.id == id }) {
            daily = site.dailyLimitMinutes
            focus = site.focusLimitMinutes
        } else if let app = settings.apps.first(where: { $0.id == id }) {
            daily = app.dailyLimitMinutes
            focus = app.focusLimitMinutes
        } else {
            return nil
        }
        if focusOn {
            if let focus { return max(0, focus) * 60 }
            if let daily { return max(0, daily) * 60 }
            return nil
        }
        if let daily { return max(0, daily) * 60 }
        return nil
    }

    var isOverOverall: Bool {
        let limit = overallLimitSeconds()
        return limit == 0 || todayTotal >= limit
    }

    /// Past the overall limit or this item's own limit.
    func isOver(_ id: String) -> Bool {
        if isOverOverall { return true }
        if let cap = itemLimitSeconds(for: id) { return seconds(for: id) >= cap }
        return false
    }

    /// Why the soft block screen should be up, if it should. Only while a tracked site or app is in front.
    func softBlockReason(currentID: String?) -> SoftBlockReason? {
        guard settings.softBlockEnabled, !isPaused else { return nil }
        let record = today
        if record.softBlockOff { return nil }
        if let until = record.snoozeUntil, until > Date() { return nil }
        guard let id = currentID else { return nil }
        let name = displayName(for: id)
        if isFocusHours(), focusMode == .block {
            return .focus(name: name, until: focusEnds())
        }
        if let cap = itemLimitSeconds(for: id), seconds(for: id) >= cap {
            return .item(name: name, used: seconds(for: id), limit: cap)
        }
        let overall = overallLimitSeconds()
        if overall > 0, todayTotal >= overall {
            return .overall(used: todayTotal, limit: overall)
        }
        return nil
    }

    func snoozeSoftBlock(minutes: Int) {
        var rec = today
        rec.snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        days[todayKey] = rec
        save()
    }

    func turnOffSoftBlockForToday() {
        var rec = today
        rec.softBlockOff = true
        rec.snoozeUntil = nil
        days[todayKey] = rec
        save()
    }

    // MARK: Friction

    func friction(for id: String) -> FrictionSettings? {
        if let site = settings.sites.first(where: { $0.id == id }) { return site.friction }
        if let app = settings.apps.first(where: { $0.id == id }) { return app.friction }
        return nil
    }

    /// The pause screen to show before this site or app, if one applies right now.
    func frictionNeeded(for id: String) -> FrictionSettings? {
        guard let f = friction(for: id), f.kind != .off else { return nil }
        switch f.trigger {
        case .always: return f
        case .focusHours: return isFocusHours() ? f : nil
        case .overLimit: return isOver(id) ? f : nil
        }
    }

    func record(_ entry: FrictionEntry) {
        log.append(entry)
        save()
    }

    func clearLog() {
        log.removeAll()
        save()
    }

    func lastReason(for id: String) -> String? {
        log.last(where: { $0.itemID == id && !($0.reason ?? "").isEmpty })?.reason
    }

    // MARK: Week

    struct WeekDay: Identifiable {
        let id: String       // day key
        let label: String
        let seconds: Int
        let isToday: Bool
    }

    func lastSevenDays() -> [WeekDay] {
        let cal = Calendar.current
        let wf = DateFormatter()
        wf.setLocalizedDateFormatFromTemplate("EEE")
        return (0..<7).reversed().compactMap { offset -> WeekDay? in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = DayKey.key(date)
            return WeekDay(id: key,
                           label: wf.string(from: date),
                           seconds: days[key]?.total ?? 0,
                           isToday: offset == 0)
        }
    }

    // MARK: Mutations
    func add(seconds: Int, to siteID: String) {
        let key = todayKey
        var rec = days[key] ?? DayRecord()
        rec.seconds[siteID, default: 0] += seconds
        days[key] = rec
    }

    func addVisit(to siteID: String) {
        let key = todayKey
        var rec = days[key] ?? DayRecord()
        rec.visits[siteID, default: 0] += 1
        days[key] = rec
    }

    func markNotified(warning: Bool) {
        let key = todayKey
        var rec = days[key] ?? DayRecord()
        if warning { rec.notifiedWarning = true } else { rec.notifiedLimit = true }
        days[key] = rec
        save()
    }

    /// Sets a per-site or per-app limit in minutes. Nil or 0 removes it. False if the id is unknown.
    @discardableResult
    func setItemLimit(_ id: String, minutes: Int?) -> Bool {
        let value = (minutes ?? 0) > 0 ? minutes : nil
        if let i = settings.sites.firstIndex(where: { $0.id == id }) {
            settings.sites[i].dailyLimitMinutes = value
            return true
        }
        if let i = settings.apps.firstIndex(where: { $0.id == id }) {
            settings.apps[i].dailyLimitMinutes = value
            return true
        }
        return false
    }

    func addSite(domain raw: String) {
        var d = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let u = URL(string: d.contains("://") ? d : "https://" + d), let h = u.host { d = h }
        if d.hasPrefix("www.") { d.removeFirst(4) }
        guard !d.isEmpty, d.contains("."), !settings.sites.contains(where: { $0.id == d }) else { return }
        let name = d.split(separator: ".").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? d
        settings.sites.append(SiteConfig(id: d, name: name, domains: [d], enabled: true, colorHex: "#8E8E93", icon: nil))
        fetchFavicon(for: d)
    }

    func addApp(bundleID: String, name: String) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        if let i = settings.apps.firstIndex(where: { $0.id == id }) {
            settings.apps[i].enabled = true
            if settings.apps[i].name.isEmpty { settings.apps[i].name = name }
            return
        }
        let title = name.isEmpty ? id : name
        settings.apps.append(AppConfig(id: id, name: title, enabled: true))
        _ = icon(forBundleID: id)
    }

    /// Reads the bundle id from an .app the user picked.
    func addApp(at url: URL) {
        let info = url.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: info),
              let bid = dict["CFBundleIdentifier"] as? String else { return }
        let name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        addApp(bundleID: bid, name: name)
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        appIcons[bid] = img
    }

    func removeApp(_ id: String) {
        settings.apps.removeAll { $0.id == id }
        appIcons[id] = nil
    }

    func icon(forBundleID bundleID: String) -> NSImage? {
        if let cached = appIcons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        appIcons[bundleID] = img
        return img
    }

    func rememberIcon(_ image: NSImage, for bundleID: String) {
        guard appIcons[bundleID] == nil else { return }
        image.size = NSSize(width: 32, height: 32)
        appIcons[bundleID] = image
    }

    /// Loads cached logos for user-added sites and fetches any that are missing.
    func loadFavicons() {
        for site in settings.sites where site.icon == nil {
            if let img = FaviconFetcher.cachedImage(for: site.id) {
                favicons[site.id] = img
            } else {
                fetchFavicon(for: site.id)
            }
        }
    }

    func fetchFavicon(for domain: String) {
        guard !faviconFetchesInFlight.contains(domain) else { return }
        faviconFetchesInFlight.insert(domain)
        Task { @MainActor [weak self] in
            let img = await FaviconFetcher.fetch(domain: domain)
            guard let self else { return }
            self.faviconFetchesInFlight.remove(domain)
            // Ignore the result if the site was removed while loading.
            if let img, self.settings.sites.contains(where: { $0.id == domain }) {
                self.favicons[domain] = img
            }
        }
    }

    func removeSite(_ id: String) {
        settings.sites.removeAll { $0.id == id }
        favicons[id] = nil
        FaviconFetcher.removeCache(for: id)
        StatusLabel.forgetFavicon(id)
    }

    func pruneOldDays(keep: Int = 90) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -keep, to: Date()) else { return }
        let cutKey = DayKey.key(cutoff)
        days = days.filter { $0.key >= cutKey }
        log = log.filter { $0.date >= cutoff }
        if let o = state.focusOverride, let until = o.until, until <= Date() { state.focusOverride = nil }
        if let p = state.pausedUntil, p <= Date() { state.pausedUntil = nil }
    }

    /// Screenshots only. Scenes refuse to run without LAPSE_DATA_DIR, so this never replaces real data.
    func replaceAll(settings: AppSettings, days: [String: DayRecord], log: [FrictionEntry], state: RuntimeState) {
        self.days = days
        self.log = log
        self.state = state
        self.settings = settings
    }

    func save() {
        let p = Persisted(settings: settings, days: days, log: log, state: state)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(p) {
            try? data.write(to: fileURL, options: .atomic)
        }
        publishToday()
    }

    /// Today's total in the app's defaults, so a Shortcuts "Run Shell Script" action can read it:
    /// defaults read com.acerothman.lapse todayMinutes
    private func publishToday() {
        guard ProcessInfo.processInfo.environment["LAPSE_DATA_DIR"] == nil,
              Bundle.main.bundleIdentifier != nil else { return }
        let defaults = UserDefaults.standard
        defaults.set(todayTotal / 60, forKey: "todayMinutes")
        defaults.set(Fmt.long(todayTotal), forKey: "todayText")
        defaults.set(limitSeconds / 60, forKey: "limitMinutes")
    }
}
