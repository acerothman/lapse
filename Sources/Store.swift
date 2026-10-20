import Foundation
import Combine
import AppKit

final class Store: ObservableObject {
    @Published var settings: AppSettings { didSet { save() } }
    @Published private(set) var days: [String: DayRecord]
    @Published var currentSiteID: String?
    /// Fetched logos for user-added sites, keyed by site id (domain).
    @Published private(set) var favicons: [String: NSImage] = [:]
    /// App icons from NSWorkspace, keyed by bundle id.
    @Published private(set) var appIcons: [String: NSImage] = [:]
    private var faviconFetchesInFlight = Set<String>()

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lapse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")

        if let data = try? Data(contentsOf: fileURL),
           let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            settings = p.settings
            days = p.days
        } else {
            settings = AppSettings()
            days = [:]
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

    func app(for bundleID: String) -> AppConfig? {
        enabledApps.first { $0.id == bundleID }
    }

    func displayName(for id: String) -> String {
        if let site = settings.sites.first(where: { $0.id == id }) { return site.name }
        if let app = settings.apps.first(where: { $0.id == id }) { return app.name }
        return id
    }

    // MARK: Focus and limits

    func isFocusHours(at date: Date = Date()) -> Bool {
        let focus = settings.focus
        guard focus.enabled else { return false }
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date) // 1 = Sunday
        let index = weekday - 1
        guard focus.days.indices.contains(index), focus.days[index] else { return false }
        let minutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let start = focus.startMinutes
        let end = focus.endMinutes
        if start == end { return true }
        if start < end { return minutes >= start && minutes < end }
        return minutes >= start || minutes < end
    }

    /// Overall cap in seconds for right now. Zero means block as soon as a tracked site or app is in front.
    func overallLimitSeconds(at date: Date = Date()) -> Int {
        if isFocusHours(at: date) {
            if settings.focus.mode == .block { return 0 }
            return max(0, settings.focus.dailyLimitMinutes) * 60
        }
        return max(0, settings.dailyLimitMinutes) * 60
    }

    /// Per-site or per-app cap in seconds, if one is set. Nil means only the overall limit applies.
    func itemLimitSeconds(for id: String, at date: Date = Date()) -> Int? {
        let focusOn = isFocusHours(at: date)
        if focusOn && settings.focus.mode == .block { return 0 }
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

    /// Why the soft block screen should be up, if it should. Only while a tracked site or app is in front.
    func softBlockReason(currentID: String?) -> SoftBlockReason? {
        guard settings.softBlockEnabled else { return nil }
        let record = today
        if record.softBlockOff { return nil }
        if let until = record.snoozeUntil, until > Date() { return nil }
        guard let id = currentID else { return nil }
        let name = displayName(for: id)
        if isFocusHours(), settings.focus.mode == .block {
            return .focus(name: name)
        }
        if let cap = itemLimitSeconds(for: id), (today.seconds[id] ?? 0) >= cap {
            return .item(name: name, used: today.seconds[id] ?? 0, limit: cap)
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

    struct WeekDay: Identifiable {
        let id: String       // day key
        let label: String
        let seconds: Int
        let isToday: Bool
    }

    func lastSevenDays() -> [WeekDay] {
        let cal = Calendar.current
        let wf = DateFormatter()
        wf.dateFormat = "EEE"
        return (0..<7).reversed().compactMap { offset -> WeekDay? in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = DayKey.key(date)
            return WeekDay(id: key,
                           label: offset == 0 ? "Today" : wf.string(from: date),
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
    }

    func save() {
        let p = Persisted(settings: settings, days: days)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(p) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
