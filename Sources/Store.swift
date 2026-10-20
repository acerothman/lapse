import Foundation
import Combine
import AppKit

final class Store: ObservableObject {
    @Published var settings: AppSettings { didSet { save() } }
    @Published private(set) var days: [String: DayRecord]
    @Published var currentSiteID: String?
    /// Fetched logos for user-added sites, keyed by site id (domain).
    @Published private(set) var favicons: [String: NSImage] = [:]
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
    var limitSeconds: Int { settings.dailyLimitMinutes * 60 }
    var enabledSites: [SiteConfig] { settings.sites.filter(\.enabled) }

    func site(for host: String) -> SiteConfig? {
        enabledSites.first { $0.matches(host: host) }
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
