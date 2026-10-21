import Foundation

enum FrictionWhen: String, Codable, Hashable, CaseIterable {
    case off, always, focus, afterLimit

    var label: String {
        switch self {
        case .off: return "Off"
        case .always: return "Always"
        case .focus: return "During focus"
        case .afterLimit: return "After the limit"
        }
    }
}

enum FrictionStyle: String, Codable, Hashable, CaseIterable {
    case countdown, ask

    var label: String {
        switch self {
        case .countdown: return "Countdown"
        case .ask: return "Ask why"
        }
    }
}

struct SiteConfig: Codable, Identifiable, Hashable {
    var id: String            // primary domain, e.g. "x.com"
    var name: String
    var domains: [String]     // all hosts that count for this site
    var enabled: Bool
    var colorHex: String
    var icon: String?         // resource name without extension, e.g. "icon-x"
    /// Extra daily cap for this site, in minutes. Nil means only the overall limit applies.
    var dailyLimitMinutes: Int? = nil
    /// Cap used during focus hours, when focus is set to stricter limits.
    var focusLimitMinutes: Int? = nil
    /// Count only the feed, not messages, composing, notifications, or settings.
    var feedOnly: Bool = false
    /// Nil uses the app-wide pause setting.
    var frictionWhen: FrictionWhen? = nil
    var frictionStyle: FrictionStyle? = nil
    var frictionSeconds: Int? = nil

    var supportsFeed: Bool {
        FeedRules.supports(siteID: id)
    }

    /// Bundled Simple Icons glyph. A saved row that lost `icon` still uses the built-in mark.
    var bundledIconName: String? {
        if let icon, !icon.isEmpty { return icon }
        return SiteConfig.defaults.first { $0.id == id }?.icon
    }

    func matches(host: String) -> Bool {
        let h = host.lowercased()
        return domains.contains { d in h == d || h.hasSuffix("." + d) }
    }

    init(id: String, name: String, domains: [String], enabled: Bool, colorHex: String, icon: String?,
         dailyLimitMinutes: Int? = nil, focusLimitMinutes: Int? = nil, feedOnly: Bool = false,
         frictionWhen: FrictionWhen? = nil, frictionStyle: FrictionStyle? = nil, frictionSeconds: Int? = nil) {
        self.id = id
        self.name = name
        self.domains = domains
        self.enabled = enabled
        self.colorHex = colorHex
        self.icon = icon
        self.dailyLimitMinutes = dailyLimitMinutes
        self.focusLimitMinutes = focusLimitMinutes
        self.feedOnly = feedOnly
        self.frictionWhen = frictionWhen
        self.frictionStyle = frictionStyle
        self.frictionSeconds = frictionSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, domains, enabled, colorHex, icon
        case dailyLimitMinutes, focusLimitMinutes, feedOnly
        case frictionWhen, frictionStyle, frictionSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        domains = try c.decodeIfPresent([String].self, forKey: .domains) ?? [id]
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#8E8E93"
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        dailyLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
        focusLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .focusLimitMinutes)
        feedOnly = try c.decodeIfPresent(Bool.self, forKey: .feedOnly) ?? (id == "x.com")
        frictionWhen = try c.decodeIfPresent(FrictionWhen.self, forKey: .frictionWhen)
        frictionStyle = try c.decodeIfPresent(FrictionStyle.self, forKey: .frictionStyle)
        frictionSeconds = try c.decodeIfPresent(Int.self, forKey: .frictionSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(domains, forKey: .domains)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        try c.encodeIfPresent(focusLimitMinutes, forKey: .focusLimitMinutes)
        try c.encode(feedOnly, forKey: .feedOnly)
        try c.encodeIfPresent(frictionWhen, forKey: .frictionWhen)
        try c.encodeIfPresent(frictionStyle, forKey: .frictionStyle)
        try c.encodeIfPresent(frictionSeconds, forKey: .frictionSeconds)
    }

    static let defaults: [SiteConfig] = [
        SiteConfig(id: "x.com", name: "X", domains: ["x.com", "twitter.com"], enabled: true, colorHex: "#000000", icon: "icon-x", feedOnly: true),
        SiteConfig(id: "instagram.com", name: "Instagram", domains: ["instagram.com"], enabled: true, colorHex: "#FF0069", icon: "icon-instagram"),
        SiteConfig(id: "tiktok.com", name: "TikTok", domains: ["tiktok.com"], enabled: true, colorHex: "#000000", icon: "icon-tiktok"),
        SiteConfig(id: "youtube.com", name: "YouTube", domains: ["youtube.com", "youtu.be"], enabled: true, colorHex: "#FF0000", icon: "icon-youtube"),
        SiteConfig(id: "reddit.com", name: "Reddit", domains: ["reddit.com"], enabled: true, colorHex: "#FF4500", icon: "icon-reddit"),
        SiteConfig(id: "facebook.com", name: "Facebook", domains: ["facebook.com", "fb.com"], enabled: false, colorHex: "#0866FF", icon: "icon-facebook"),
        SiteConfig(id: "threads.net", name: "Threads", domains: ["threads.net"], enabled: false, colorHex: "#000000", icon: "icon-threads"),
        SiteConfig(id: "linkedin.com", name: "LinkedIn", domains: ["linkedin.com"], enabled: false, colorHex: "#0A66C2", icon: "icon-linkedin"),
        SiteConfig(id: "snapchat.com", name: "Snapchat", domains: ["snapchat.com"], enabled: false, colorHex: "#FFFC00", icon: "icon-snapchat"),
        SiteConfig(id: "twitch.tv", name: "Twitch", domains: ["twitch.tv", "twitch.com"], enabled: false, colorHex: "#9146FF", icon: "icon-twitch"),
    ]
}

/// A Mac app tracked by its bundle id. The icon comes from NSWorkspace, not a bundled PNG.
struct AppConfig: Codable, Identifiable, Hashable {
    var id: String            // bundle identifier
    var name: String
    var enabled: Bool
    var dailyLimitMinutes: Int? = nil
    var focusLimitMinutes: Int? = nil
    var frictionWhen: FrictionWhen? = nil
    var frictionStyle: FrictionStyle? = nil
    var frictionSeconds: Int? = nil

    init(id: String, name: String, enabled: Bool, dailyLimitMinutes: Int? = nil, focusLimitMinutes: Int? = nil,
         frictionWhen: FrictionWhen? = nil, frictionStyle: FrictionStyle? = nil, frictionSeconds: Int? = nil) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.dailyLimitMinutes = dailyLimitMinutes
        self.focusLimitMinutes = focusLimitMinutes
        self.frictionWhen = frictionWhen
        self.frictionStyle = frictionStyle
        self.frictionSeconds = frictionSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, dailyLimitMinutes, focusLimitMinutes
        case frictionWhen, frictionStyle, frictionSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        dailyLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
        focusLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .focusLimitMinutes)
        frictionWhen = try c.decodeIfPresent(FrictionWhen.self, forKey: .frictionWhen)
        frictionStyle = try c.decodeIfPresent(FrictionStyle.self, forKey: .frictionStyle)
        frictionSeconds = try c.decodeIfPresent(Int.self, forKey: .frictionSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(enabled, forKey: .enabled)
        try c.encodeIfPresent(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        try c.encodeIfPresent(focusLimitMinutes, forKey: .focusLimitMinutes)
        try c.encodeIfPresent(frictionWhen, forKey: .frictionWhen)
        try c.encodeIfPresent(frictionStyle, forKey: .frictionStyle)
        try c.encodeIfPresent(frictionSeconds, forKey: .frictionSeconds)
    }

    /// The Mac App Store build of X is the iPad app, bundle id com.atebits.Tweetie2.
    /// The older Catalyst build used maccatalyst.com.atebits.Tweetie2.
    static let defaults: [AppConfig] = [
        AppConfig(id: "com.atebits.Tweetie2", name: "X", enabled: false),
        AppConfig(id: "com.hnc.Discord", name: "Discord", enabled: false),
        AppConfig(id: "com.tinyspeck.slackmacgap", name: "Slack", enabled: false),
        AppConfig(id: "com.apple.MobileSMS", name: "Messages", enabled: false),
    ]
}

enum FocusMode: String, Codable {
    case stricter
    case block
}

struct FocusSettings: Codable, Hashable {
    var enabled: Bool = false
    /// Sunday through Saturday, matching Calendar weekday order.
    var days: [Bool] = [false, true, true, true, true, true, false]
    var startMinutes: Int = 9 * 60
    var endMinutes: Int = 17 * 60
    var mode: FocusMode = .stricter
    /// Overall daily limit used while focus hours are on, in stricter mode.
    var dailyLimitMinutes: Int = 30
    /// On until Stop focus, even outside the clock window.
    var manualOn: Bool = false

    private enum CodingKeys: String, CodingKey {
        case enabled, days, startMinutes, endMinutes, mode, dailyLimitMinutes, manualOn
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        days = try c.decodeIfPresent([Bool].self, forKey: .days) ?? [false, true, true, true, true, true, false]
        startMinutes = try c.decodeIfPresent(Int.self, forKey: .startMinutes) ?? 9 * 60
        endMinutes = try c.decodeIfPresent(Int.self, forKey: .endMinutes) ?? 17 * 60
        mode = try c.decodeIfPresent(FocusMode.self, forKey: .mode) ?? .stricter
        dailyLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes) ?? 30
        manualOn = try c.decodeIfPresent(Bool.self, forKey: .manualOn) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(days, forKey: .days)
        try c.encode(startMinutes, forKey: .startMinutes)
        try c.encode(endMinutes, forKey: .endMinutes)
        try c.encode(mode, forKey: .mode)
        try c.encode(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        try c.encode(manualOn, forKey: .manualOn)
    }
}

enum SessionPhase: String, Codable, Equatable {
    case focus, shortBreak, longBreak
}

/// Lengths for the lock-in timer. Preset 25 or 50 matches the popover. 0 means custom.
struct SessionSettings: Codable, Hashable {
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var roundsUntilLong: Int = 4
    var hideApps: Bool = true
    var customMinutes: Int = 45
    var preset: Int = 25

    init() {}

    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, roundsUntilLong
        case hideApps, customMinutes, preset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = try c.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15
        roundsUntilLong = try c.decodeIfPresent(Int.self, forKey: .roundsUntilLong) ?? 4
        hideApps = try c.decodeIfPresent(Bool.self, forKey: .hideApps) ?? true
        customMinutes = try c.decodeIfPresent(Int.self, forKey: .customMinutes) ?? 45
        preset = try c.decodeIfPresent(Int.self, forKey: .preset) ?? 25
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(focusMinutes, forKey: .focusMinutes)
        try c.encode(shortBreakMinutes, forKey: .shortBreakMinutes)
        try c.encode(longBreakMinutes, forKey: .longBreakMinutes)
        try c.encode(roundsUntilLong, forKey: .roundsUntilLong)
        try c.encode(hideApps, forKey: .hideApps)
        try c.encode(customMinutes, forKey: .customMinutes)
        try c.encode(preset, forKey: .preset)
    }
}

struct ActiveSession: Codable, Equatable {
    var phase: SessionPhase
    var endsAt: Date
    var pausedRemaining: TimeInterval?
    var completedInCycle: Int
    var startedAt: Date
    var fromSystemFocus: Bool
    var blockedAttempts: Int
    var lastBlockedID: String?
    var plannedMinutes: Int

    private enum CodingKeys: String, CodingKey {
        case phase, endsAt, pausedRemaining, completedInCycle, startedAt
        case fromSystemFocus, blockedAttempts, lastBlockedID, plannedMinutes
    }

    init(phase: SessionPhase, endsAt: Date, pausedRemaining: TimeInterval?, completedInCycle: Int,
         startedAt: Date, fromSystemFocus: Bool, blockedAttempts: Int, lastBlockedID: String?, plannedMinutes: Int) {
        self.phase = phase
        self.endsAt = endsAt
        self.pausedRemaining = pausedRemaining
        self.completedInCycle = completedInCycle
        self.startedAt = startedAt
        self.fromSystemFocus = fromSystemFocus
        self.blockedAttempts = blockedAttempts
        self.lastBlockedID = lastBlockedID
        self.plannedMinutes = plannedMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decodeIfPresent(SessionPhase.self, forKey: .phase) ?? .focus
        endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAt) ?? Date()
        pausedRemaining = try c.decodeIfPresent(TimeInterval.self, forKey: .pausedRemaining)
        completedInCycle = try c.decodeIfPresent(Int.self, forKey: .completedInCycle) ?? 0
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? endsAt
        fromSystemFocus = try c.decodeIfPresent(Bool.self, forKey: .fromSystemFocus) ?? false
        blockedAttempts = try c.decodeIfPresent(Int.self, forKey: .blockedAttempts) ?? 0
        lastBlockedID = try c.decodeIfPresent(String.self, forKey: .lastBlockedID)
        plannedMinutes = try c.decodeIfPresent(Int.self, forKey: .plannedMinutes) ?? 25
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phase, forKey: .phase)
        try c.encode(endsAt, forKey: .endsAt)
        try c.encodeIfPresent(pausedRemaining, forKey: .pausedRemaining)
        try c.encode(completedInCycle, forKey: .completedInCycle)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(fromSystemFocus, forKey: .fromSystemFocus)
        try c.encode(blockedAttempts, forKey: .blockedAttempts)
        try c.encodeIfPresent(lastBlockedID, forKey: .lastBlockedID)
        try c.encode(plannedMinutes, forKey: .plannedMinutes)
    }
}

struct SessionEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var phase: SessionPhase
    var startedAt: Date
    var endedAt: Date
    var plannedMinutes: Int
    var completed: Bool

    private enum CodingKeys: String, CodingKey {
        case id, phase, startedAt, endedAt, plannedMinutes, completed
    }

    init(id: UUID, phase: SessionPhase, startedAt: Date, endedAt: Date, plannedMinutes: Int, completed: Bool) {
        self.id = id
        self.phase = phase
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedMinutes = plannedMinutes
        self.completed = completed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        phase = try c.decodeIfPresent(SessionPhase.self, forKey: .phase) ?? .focus
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt) ?? startedAt
        plannedMinutes = try c.decodeIfPresent(Int.self, forKey: .plannedMinutes) ?? 25
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(phase, forKey: .phase)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(plannedMinutes, forKey: .plannedMinutes)
        try c.encode(completed, forKey: .completed)
    }
}

/// What the full-screen block is covering. The countdown comes from the active session.
struct BlockTarget: Equatable {
    var id: String
    var name: String
}

struct DayRecord: Codable {
    var seconds: [String: Int] = [:]   // site id or bundle id -> seconds
    var visits: [String: Int] = [:]    // site id or bundle id -> visit count
    var notifiedWarning = false
    var notifiedLimit = false
    /// The soft block screen stays hidden for the rest of the day.
    var softBlockOff = false
    /// Hide the soft block screen until this time.
    var snoozeUntil: Date? = nil

    var total: Int { seconds.values.reduce(0, +) }

    private enum CodingKeys: String, CodingKey {
        case seconds, visits, notifiedWarning, notifiedLimit, softBlockOff, snoozeUntil
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seconds = try c.decodeIfPresent([String: Int].self, forKey: .seconds) ?? [:]
        visits = try c.decodeIfPresent([String: Int].self, forKey: .visits) ?? [:]
        notifiedWarning = try c.decodeIfPresent(Bool.self, forKey: .notifiedWarning) ?? false
        notifiedLimit = try c.decodeIfPresent(Bool.self, forKey: .notifiedLimit) ?? false
        softBlockOff = try c.decodeIfPresent(Bool.self, forKey: .softBlockOff) ?? false
        snoozeUntil = try c.decodeIfPresent(Date.self, forKey: .snoozeUntil)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(seconds, forKey: .seconds)
        try c.encode(visits, forKey: .visits)
        try c.encode(notifiedWarning, forKey: .notifiedWarning)
        try c.encode(notifiedLimit, forKey: .notifiedLimit)
        try c.encode(softBlockOff, forKey: .softBlockOff)
        try c.encodeIfPresent(snoozeUntil, forKey: .snoozeUntil)
    }
}

struct AppSettings: Codable {
    var dailyLimitMinutes: Int = 90
    var idleThresholdSeconds: Int = 60
    var notificationsEnabled: Bool = true
    /// Full-screen screen when a limit is reached. Off means tracking continues with no overlay.
    var softBlockEnabled: Bool = true
    var sites: [SiteConfig] = SiteConfig.defaults
    var apps: [AppConfig] = AppConfig.defaults
    var focus: FocusSettings = FocusSettings()
    /// False until the welcome window is finished. Missing in older files, so decode it by hand.
    var didFinishOnboarding: Bool = false
    var trackingPaused: Bool = false
    var frictionWhen: FrictionWhen = .off
    var frictionStyle: FrictionStyle = .countdown
    var frictionSeconds: Int = 10
    var session: SessionSettings = SessionSettings()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case dailyLimitMinutes, idleThresholdSeconds, notificationsEnabled, softBlockEnabled
        case sites, apps, focus, didFinishOnboarding
        case trackingPaused, frictionWhen, frictionStyle, frictionSeconds, session
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes) ?? 90
        idleThresholdSeconds = try c.decodeIfPresent(Int.self, forKey: .idleThresholdSeconds) ?? 60
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        softBlockEnabled = try c.decodeIfPresent(Bool.self, forKey: .softBlockEnabled) ?? true
        sites = try c.decodeIfPresent([SiteConfig].self, forKey: .sites) ?? SiteConfig.defaults
        apps = try c.decodeIfPresent([AppConfig].self, forKey: .apps) ?? AppConfig.defaults
        focus = try c.decodeIfPresent(FocusSettings.self, forKey: .focus) ?? FocusSettings()
        didFinishOnboarding = try c.decodeIfPresent(Bool.self, forKey: .didFinishOnboarding) ?? false
        trackingPaused = try c.decodeIfPresent(Bool.self, forKey: .trackingPaused) ?? false
        frictionWhen = try c.decodeIfPresent(FrictionWhen.self, forKey: .frictionWhen) ?? .off
        frictionStyle = try c.decodeIfPresent(FrictionStyle.self, forKey: .frictionStyle) ?? .countdown
        frictionSeconds = try c.decodeIfPresent(Int.self, forKey: .frictionSeconds) ?? 10
        session = try c.decodeIfPresent(SessionSettings.self, forKey: .session) ?? SessionSettings()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        try c.encode(idleThresholdSeconds, forKey: .idleThresholdSeconds)
        try c.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try c.encode(softBlockEnabled, forKey: .softBlockEnabled)
        try c.encode(sites, forKey: .sites)
        try c.encode(apps, forKey: .apps)
        try c.encode(focus, forKey: .focus)
        try c.encode(didFinishOnboarding, forKey: .didFinishOnboarding)
        try c.encode(trackingPaused, forKey: .trackingPaused)
        try c.encode(frictionWhen, forKey: .frictionWhen)
        try c.encode(frictionStyle, forKey: .frictionStyle)
        try c.encode(frictionSeconds, forKey: .frictionSeconds)
        try c.encode(session, forKey: .session)
    }
}

struct FrictionNote: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var targetID: String
    var name: String
    var reason: String
}

struct Persisted: Codable {
    var settings: AppSettings
    var days: [String: DayRecord]
    var frictionNotes: [FrictionNote]
    var activeSession: ActiveSession?
    var sessionLog: [SessionEntry]

    init(settings: AppSettings, days: [String: DayRecord], frictionNotes: [FrictionNote] = [],
         activeSession: ActiveSession? = nil, sessionLog: [SessionEntry] = []) {
        self.settings = settings
        self.days = days
        self.frictionNotes = frictionNotes
        self.activeSession = activeSession
        self.sessionLog = sessionLog
    }

    private enum CodingKeys: String, CodingKey {
        case settings, days, frictionNotes, activeSession, sessionLog
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decode(AppSettings.self, forKey: .settings)
        days = try c.decodeIfPresent([String: DayRecord].self, forKey: .days) ?? [:]
        frictionNotes = try c.decodeIfPresent([FrictionNote].self, forKey: .frictionNotes) ?? []
        activeSession = try c.decodeIfPresent(ActiveSession.self, forKey: .activeSession)
        sessionLog = try c.decodeIfPresent([SessionEntry].self, forKey: .sessionLog) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(settings, forKey: .settings)
        try c.encode(days, forKey: .days)
        try c.encode(frictionNotes, forKey: .frictionNotes)
        try c.encodeIfPresent(activeSession, forKey: .activeSession)
        try c.encode(sessionLog, forKey: .sessionLog)
    }
}

enum DayKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func key(_ date: Date = Date()) -> String { formatter.string(from: date) }
}

enum SoftBlockReason: Equatable {
    case overall(used: Int, limit: Int)
    case item(name: String, used: Int, limit: Int)
    case focus(name: String)

    var title: String {
        switch self {
        case .overall: return "Daily limit reached"
        case .item(let name, _, _): return "That's enough \(name)"
        case .focus: return "Focus hours"
        }
    }

    var detail: String {
        switch self {
        case .overall(let used, let limit):
            return "You've used \(Fmt.long(used)) today. The limit is \(Fmt.long(limit))."
        case .item(let name, let used, let limit):
            return "You've spent \(Fmt.long(used)) in \(name). The limit is \(Fmt.long(limit))."
        case .focus(let name):
            return "\(name) waits until focus hours are over."
        }
    }
}

enum Fmt {
    /// "2 h 24 min", "41 min", "0 min"
    static func long(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        if m >= 60 {
            let h = m / 60, r = m % 60
            return r == 0 ? "\(h) h" : "\(h) h \(r) min"
        }
        return "\(m) min"
    }
    /// Session timer: "4:12", or "1:02:09" past an hour.
    static func session(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
    /// "2:24"
    static func clock(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        return String(format: "%d:%02d", m / 60, m % 60)
    }
    /// "1h 12m", "12m", "0m"
    static func compact(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        if m >= 60 {
            let h = m / 60, r = m % 60
            return r == 0 ? "\(h)h" : "\(h)h \(r)m"
        }
        return "\(m)m"
    }
    /// Clock time without a date, such as "10:25".
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f.string(from: date)
    }
}

extension Notification.Name {
    static let lapseChrome = Notification.Name("lapse.chrome")
}
