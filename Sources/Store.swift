import Foundation
import Combine
import AppKit

final class Store: ObservableObject {
    static let shared = Store()

    @Published var settings: AppSettings { didSet { save() } }
    @Published private(set) var days: [String: DayRecord]
    @Published private(set) var frictionNotes: [FrictionNote] = []
    @Published var currentSiteID: String?
    /// Set while a macOS Focus filter is on. Not written to disk.
    @Published var systemFocusActive = false
    @Published var systemFocusMode: FocusMode = .stricter
    @Published var frictionRequest: FrictionRequest?
    var frictionClearedID: String?
    var frictionHoldID: String?
    /// Running pomodoro. Nil when idle. Written with the rest of the file.
    @Published var activeSession: ActiveSession?
    @Published private(set) var sessionLog: [SessionEntry] = []
    /// Bumped about once a second so the countdown redraws. Not saved.
    @Published var clock = Date()
    /// Set while a blocked site or app is in front during focus.
    @Published var blockTarget: BlockTarget?
    /// The end-early hold or question is on screen.
    @Published var endEarlyVisible = false
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
            frictionNotes = p.frictionNotes
            activeSession = p.activeSession
            sessionLog = p.sessionLog
        } else {
            settings = AppSettings()
            days = [:]
            frictionNotes = []
        }
        migrateXBundleID()
        catchUpSession()
    }

    /// 1.1 guessed com.x.twitter. The shipping Mac app is com.atebits.Tweetie2.
    private func migrateXBundleID() {
        guard let index = settings.apps.firstIndex(where: { $0.id == "com.x.twitter" }),
              !settings.apps.contains(where: { $0.id == "com.atebits.Tweetie2" }) else { return }
        settings.apps[index].id = "com.atebits.Tweetie2"
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

    func setSystemFocus(active: Bool, mode: FocusMode) {
        systemFocusActive = active
        systemFocusMode = mode
    }

    func activeFocusMode() -> FocusMode {
        systemFocusActive ? systemFocusMode : settings.focus.mode
    }

    func isFocusHours(at date: Date = Date()) -> Bool {
        if systemFocusActive { return true }
        let focus = settings.focus
        guard focus.enabled else { return false }
        if focus.manualOn { return true }
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
            if activeFocusMode() == .block { return 0 }
            return max(0, settings.focus.dailyLimitMinutes) * 60
        }
        return max(0, settings.dailyLimitMinutes) * 60
    }

    /// Per-site or per-app cap in seconds, if one is set. Nil means only the overall limit applies.
    func itemLimitSeconds(for id: String, at date: Date = Date()) -> Int? {
        let focusOn = isFocusHours(at: date)
        if focusOn && activeFocusMode() == .block { return 0 }
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
        if isFocusHours(), activeFocusMode() == .block {
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

    func frictionWhen(for id: String) -> FrictionWhen {
        if let site = settings.sites.first(where: { $0.id == id }), let when = site.frictionWhen { return when }
        if let app = settings.apps.first(where: { $0.id == id }), let when = app.frictionWhen { return when }
        return settings.frictionWhen
    }

    func frictionStyle(for id: String) -> FrictionStyle {
        if let site = settings.sites.first(where: { $0.id == id }), let style = site.frictionStyle { return style }
        if let app = settings.apps.first(where: { $0.id == id }), let style = app.frictionStyle { return style }
        return settings.frictionStyle
    }

    func frictionLength(for id: String) -> Int {
        let raw: Int
        if let site = settings.sites.first(where: { $0.id == id }), let seconds = site.frictionSeconds {
            raw = seconds
        } else if let app = settings.apps.first(where: { $0.id == id }), let seconds = app.frictionSeconds {
            raw = seconds
        } else {
            raw = settings.frictionSeconds
        }
        return min(60, max(3, raw))
    }

    func needsFriction(for id: String) -> Bool {
        switch frictionWhen(for: id) {
        case .off:
            return false
        case .always:
            return true
        case .focus:
            return isFocusHours()
        case .afterLimit:
            if isFocusHours(), activeFocusMode() == .block { return true }
            let limit = overallLimitSeconds()
            if limit > 0, todayTotal >= limit { return true }
            if let cap = itemLimitSeconds(for: id), (today.seconds[id] ?? 0) >= cap { return true }
            return false
        }
    }

    func presentFriction(for id: String) {
        guard frictionRequest?.targetID != id else { return }
        frictionRequest = FrictionRequest(targetID: id,
                                          name: displayName(for: id),
                                          style: frictionStyle(for: id),
                                          seconds: frictionLength(for: id))
    }

    func passFriction(reason: String?) {
        guard let request = frictionRequest else { return }
        if let reason {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                frictionNotes.insert(FrictionNote(id: UUID(), date: Date(), targetID: request.targetID, name: request.name, reason: trimmed), at: 0)
                if frictionNotes.count > 100 { frictionNotes.removeLast(frictionNotes.count - 100) }
            }
        }
        frictionClearedID = request.targetID
        frictionHoldID = nil
        frictionRequest = nil
        save()
    }

    func declineFriction() {
        frictionHoldID = frictionRequest?.targetID
        frictionRequest = nil
    }

    func clearFrictionVisit() {
        frictionClearedID = nil
        frictionHoldID = nil
        if frictionRequest != nil { frictionRequest = nil }
    }

    func save() {
        let p = Persisted(settings: settings, days: days, frictionNotes: frictionNotes,
                          activeSession: activeSession, sessionLog: sessionLog)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(p) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Sessions

    var sessionLocksApps: Bool { activeSession?.phase == .focus }

    func upcomingFocusMinutes() -> Int {
        let session = settings.session
        let raw = session.preset == 0 ? session.customMinutes : session.preset
        return min(180, max(1, raw))
    }

    func isLocking(_ id: String) -> Bool {
        guard sessionLocksApps else { return false }
        if settings.sites.contains(where: { $0.enabled && $0.id == id }) { return true }
        if settings.apps.contains(where: { $0.enabled && $0.id == id }) { return true }
        return false
    }

    func remainingSeconds() -> Int {
        guard let session = activeSession else { return 0 }
        let raw = session.pausedRemaining ?? session.endsAt.timeIntervalSince(clock)
        return max(0, Int(ceil(raw)))
    }

    func sessionFraction() -> Double {
        guard let session = activeSession else { return 0 }
        let total = TimeInterval(max(session.plannedMinutes, 1) * 60)
        let left = session.pausedRemaining ?? max(0, session.endsAt.timeIntervalSince(clock))
        return min(1, max(0, 1 - left / total))
    }

    func dotCount() -> Int { min(8, max(1, settings.session.roundsUntilLong)) }

    func filledDotCount() -> Int {
        guard let session = activeSession else { return 0 }
        let total = dotCount()
        switch session.phase {
        case .focus: return min(total, session.completedInCycle + 1)
        case .shortBreak, .longBreak: return min(total, session.completedInCycle)
        }
    }

    func sessionCaption() -> String {
        guard let session = activeSession else { return "Focus" }
        if session.pausedRemaining != nil, session.phase == .focus { return "Paused" }
        let rounds = dotCount()
        switch session.phase {
        case .focus:
            let n = min(rounds, session.completedInCycle + 1)
            return "Until break · \(n) of \(rounds)"
        case .shortBreak, .longBreak:
            let n = min(rounds, max(1, session.completedInCycle))
            return "Until focus · \(n) of \(rounds)"
        }
    }

    func phaseTitle() -> String {
        guard let session = activeSession else { return "Focus" }
        if session.pausedRemaining != nil, session.phase == .focus { return "Paused" }
        switch session.phase {
        case .focus: return "Focus"
        case .shortBreak, .longBreak: return "Break"
        }
    }

    struct TargetStat: Identifiable {
        var id: String
        var name: String
        var seconds: Int
    }

    func topTargets(_ limit: Int = 3) -> [TargetStat] {
        let today = today
        var rows: [TargetStat] = []
        for site in settings.sites where site.enabled {
            rows.append(TargetStat(id: site.id, name: site.name, seconds: today.seconds[site.id] ?? 0))
        }
        for app in settings.apps where app.enabled {
            rows.append(TargetStat(id: app.id, name: app.name, seconds: today.seconds[app.id] ?? 0))
        }
        return Array(rows.sorted { $0.seconds > $1.seconds }.prefix(limit))
    }

    func todayFocusCount() -> Int {
        let key = todayKey
        return sessionLog.filter { $0.completed && $0.phase == .focus && DayKey.key($0.endedAt) == key }.count
    }

    func focusStreak() -> Int {
        let done = Set(sessionLog.filter { $0.completed && $0.phase == .focus }.map { DayKey.key($0.endedAt) })
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: Date())
        if !done.contains(DayKey.key(cursor)) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var streak = 0
        while done.contains(DayKey.key(cursor)) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    func selectPreset(_ preset: Int) {
        var session = settings.session
        session.preset = preset
        if preset == 25 || preset == 50 {
            session.focusMinutes = preset
        } else {
            session.focusMinutes = min(180, max(1, session.customMinutes))
        }
        settings.session = session
    }

    func setCustomMinutes(_ minutes: Int) {
        let clamped = min(180, max(1, minutes))
        var session = settings.session
        session.preset = 0
        session.customMinutes = clamped
        session.focusMinutes = clamped
        settings.session = session
    }

    func alignPresetWithFocusLength() {
        var session = settings.session
        let minutes = min(180, max(1, session.focusMinutes))
        session.focusMinutes = minutes
        if minutes == 25 {
            session.preset = 25
        } else if minutes == 50 {
            session.preset = 50
        } else {
            session.preset = 0
            session.customMinutes = minutes
        }
        if session != settings.session { settings.session = session }
    }

    func startSession(fromSystemFocus: Bool) {
        guard activeSession == nil else { return }
        frictionRequest = nil
        let minutes = upcomingFocusMinutes()
        var session = settings.session
        session.focusMinutes = minutes
        if session != settings.session { settings.session = session }
        let start = Date()
        activeSession = ActiveSession(phase: .focus,
                                       endsAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
                                       pausedRemaining: nil,
                                       completedInCycle: 0,
                                       startedAt: start,
                                       fromSystemFocus: fromSystemFocus,
                                       blockedAttempts: 0,
                                       lastBlockedID: nil,
                                       plannedMinutes: minutes)
        clock = start
        save()
        NotificationCenter.default.post(name: .lapseChrome, object: nil)
    }

    func togglePauseSession() {
        guard var session = activeSession, session.phase == .focus else { return }
        if let left = session.pausedRemaining {
            session.pausedRemaining = nil
            session.endsAt = Date().addingTimeInterval(max(0, left))
        } else {
            session.pausedRemaining = max(0, session.endsAt.timeIntervalSinceNow)
        }
        activeSession = session
        save()
        NotificationCenter.default.post(name: .lapseChrome, object: nil)
    }

    func skipBreak() {
        guard var session = activeSession, session.phase != .focus else { return }
        session.endsAt = Date()
        activeSession = session
        catchUpSession()
    }

    func requestEndEarly() {
        guard activeSession != nil else { return }
        endEarlyVisible = true
        NotificationCenter.default.post(name: .lapseChrome, object: nil)
    }

    func cancelEndEarly() {
        endEarlyVisible = false
        NotificationCenter.default.post(name: .lapseChrome, object: nil)
    }

    func endSession(reason: String?) {
        guard let session = activeSession else {
            endEarlyVisible = false
            return
        }
        if session.phase == .focus {
            logFocus(session, endedAt: Date(), completed: false)
        }
        if let reason {
            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                frictionNotes.insert(FrictionNote(id: UUID(), date: Date(), targetID: "session", name: "Session", reason: trimmed), at: 0)
                if frictionNotes.count > 100 { frictionNotes.removeLast(frictionNotes.count - 100) }
            }
        }
        activeSession = nil
        blockTarget = nil
        endEarlyVisible = false
        save()
        NotificationCenter.default.post(name: .lapseChrome, object: nil)
    }

    func noteBlocked(id: String) {
        guard var session = activeSession, session.phase == .focus else { return }
        guard session.lastBlockedID != id else { return }
        session.blockedAttempts += 1
        session.lastBlockedID = id
        activeSession = session
        save()
    }

    func suppressVisitFriction() {
        if frictionRequest != nil { frictionRequest = nil }
    }

    /// Moves a finished phase forward. A long gap is capped so a closed laptop cannot write a huge log.
    func catchUpSession(now: Date = Date()) {
        clock = now
        guard var session = activeSession, session.pausedRemaining == nil else { return }
        var changed = false
        var steps = 0
        while session.endsAt <= now && steps < 48 {
            steps += 1
            changed = true
            switch session.phase {
            case .focus:
                logFocus(session, endedAt: session.endsAt, completed: true)
                let rounds = max(1, settings.session.roundsUntilLong)
                session.completedInCycle += 1
                let long = session.completedInCycle >= rounds
                let minutes = max(1, long ? settings.session.longBreakMinutes : settings.session.shortBreakMinutes)
                session.phase = long ? .longBreak : .shortBreak
                session.startedAt = session.endsAt
                session.endsAt = session.startedAt.addingTimeInterval(TimeInterval(minutes * 60))
                session.plannedMinutes = minutes
                session.lastBlockedID = nil
            case .shortBreak:
                let minutes = max(1, settings.session.focusMinutes)
                session.phase = .focus
                session.startedAt = session.endsAt
                session.endsAt = session.startedAt.addingTimeInterval(TimeInterval(minutes * 60))
                session.plannedMinutes = minutes
                session.lastBlockedID = nil
            case .longBreak:
                let minutes = max(1, settings.session.focusMinutes)
                session.phase = .focus
                session.completedInCycle = 0
                session.startedAt = session.endsAt
                session.endsAt = session.startedAt.addingTimeInterval(TimeInterval(minutes * 60))
                session.plannedMinutes = minutes
                session.lastBlockedID = nil
            }
        }
        if steps >= 48 && session.endsAt <= now {
            activeSession = nil
            blockTarget = nil
            endEarlyVisible = false
            save()
            NotificationCenter.default.post(name: .lapseChrome, object: nil)
            return
        }
        guard changed else { return }
        activeSession = session
        if session.phase != .focus { blockTarget = nil }
        save()
        NotificationCenter.default.post(name: .lapseChrome, object: nil)
    }

    private func logFocus(_ session: ActiveSession, endedAt: Date, completed: Bool) {
        let entry = SessionEntry(id: UUID(), phase: .focus, startedAt: session.startedAt, endedAt: endedAt,
                                 plannedMinutes: session.plannedMinutes, completed: completed)
        sessionLog.insert(entry, at: 0)
        if sessionLog.count > 200 { sessionLog.removeLast(sessionLog.count - 200) }
    }
}
