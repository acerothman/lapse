import Foundation

/// What happens before a tracked site or app opens.
enum FrictionKind: String, Codable, CaseIterable, Identifiable {
    case off
    case countdown
    case reason

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .countdown: return "Countdown"
        case .reason: return "Type a reason"
        }
    }
}

/// When the pause screen shows up.
enum FrictionTrigger: String, Codable, CaseIterable, Identifiable {
    case always
    case focusHours
    case overLimit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .always: return "Every time"
        case .focusHours: return "During focus hours"
        case .overLimit: return "After a limit"
        }
    }
}

struct FrictionSettings: Codable, Hashable {
    var kind: FrictionKind = .off
    /// Countdown length in seconds.
    var seconds: Int = 10
    var trigger: FrictionTrigger = .always

    static let lengths = [5, 10, 20, 30, 60]

    init(kind: FrictionKind = .off, seconds: Int = 10, trigger: FrictionTrigger = .always) {
        self.kind = kind
        self.seconds = seconds
        self.trigger = trigger
    }

    private enum CodingKeys: String, CodingKey { case kind, seconds, trigger }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(FrictionKind.self, forKey: .kind)) ?? .off
        seconds = (try? c.decodeIfPresent(Int.self, forKey: .seconds)) ?? 10
        trigger = (try? c.decodeIfPresent(FrictionTrigger.self, forKey: .trigger)) ?? .always
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
    /// Count only the feed (see FeedRules). Ignored for sites without feed rules.
    var feedOnly: Bool = false
    var friction = FrictionSettings()

    init(id: String, name: String, domains: [String], enabled: Bool, colorHex: String, icon: String?,
         dailyLimitMinutes: Int? = nil, focusLimitMinutes: Int? = nil, feedOnly: Bool = false,
         friction: FrictionSettings = FrictionSettings()) {
        self.id = id
        self.name = name
        self.domains = domains
        self.enabled = enabled
        self.colorHex = colorHex
        self.icon = icon
        self.dailyLimitMinutes = dailyLimitMinutes
        self.focusLimitMinutes = focusLimitMinutes
        self.feedOnly = feedOnly
        self.friction = friction
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, domains, enabled, colorHex, icon, dailyLimitMinutes, focusLimitMinutes, feedOnly, friction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        domains = try c.decodeIfPresent([String].self, forKey: .domains) ?? [id]
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#8E8E93"
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        dailyLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
        focusLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .focusLimitMinutes)
        // Files from 1.1 have no key. X starts on feed only, like a new install.
        feedOnly = try c.decodeIfPresent(Bool.self, forKey: .feedOnly) ?? (id == "x.com")
        friction = try c.decodeIfPresent(FrictionSettings.self, forKey: .friction) ?? FrictionSettings()
    }

    func matches(host: String) -> Bool {
        let h = host.lowercased()
        return domains.contains { d in h == d || h.hasSuffix("." + d) }
    }

    /// True when feed-only is on and this site has feed rules.
    var countsFeedOnly: Bool { feedOnly && FeedRules.rule(for: id) != nil }

    static let defaults: [SiteConfig] = [
        SiteConfig(id: "x.com", name: "X", domains: ["x.com", "twitter.com"], enabled: true, colorHex: "#000000", icon: "icon-x", feedOnly: true),
        SiteConfig(id: "instagram.com", name: "Instagram", domains: ["instagram.com"], enabled: true, colorHex: "#FF0069", icon: "icon-instagram"),
        SiteConfig(id: "tiktok.com", name: "TikTok", domains: ["tiktok.com"], enabled: true, colorHex: "#000000", icon: "icon-tiktok"),
        SiteConfig(id: "youtube.com", name: "YouTube", domains: ["youtube.com", "youtu.be"], enabled: true, colorHex: "#FF0000", icon: "icon-youtube"),
        SiteConfig(id: "reddit.com", name: "Reddit", domains: ["reddit.com"], enabled: true, colorHex: "#FF4500", icon: "icon-reddit"),
        SiteConfig(id: "facebook.com", name: "Facebook", domains: ["facebook.com", "fb.com"], enabled: false, colorHex: "#0866FF", icon: "icon-facebook"),
        SiteConfig(id: "threads.net", name: "Threads", domains: ["threads.net", "threads.com"], enabled: false, colorHex: "#000000", icon: "icon-threads"),
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
    var friction = FrictionSettings()

    init(id: String, name: String, enabled: Bool, dailyLimitMinutes: Int? = nil,
         focusLimitMinutes: Int? = nil, friction: FrictionSettings = FrictionSettings()) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.dailyLimitMinutes = dailyLimitMinutes
        self.focusLimitMinutes = focusLimitMinutes
        self.friction = friction
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, dailyLimitMinutes, focusLimitMinutes, friction
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        dailyLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
        focusLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .focusLimitMinutes)
        friction = try c.decodeIfPresent(FrictionSettings.self, forKey: .friction) ?? FrictionSettings()
    }

    /// X on the Mac is the iPad app from the App Store, so it reports the iOS bundle id.
    static let xBundleID = "com.atebits.Tweetie2"
    /// What 1.1 shipped for X. No Mac app uses it.
    static let oldXBundleID = "com.x.twitter"

    static let defaults: [AppConfig] = [
        AppConfig(id: xBundleID, name: "X", enabled: false),
        AppConfig(id: "com.hnc.Discord", name: "Discord", enabled: false),
        AppConfig(id: "com.tinyspeck.slackmacgap", name: "Slack", enabled: false),
        AppConfig(id: "com.apple.MobileSMS", name: "Messages", enabled: false),
    ]
}

enum FocusMode: String, Codable, CaseIterable {
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

    init() {}

    private enum CodingKeys: String, CodingKey {
        case dailyLimitMinutes, idleThresholdSeconds, notificationsEnabled, softBlockEnabled
        case sites, apps, focus, didFinishOnboarding
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
        migrate()
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
    }

    /// Fixes defaults that older versions got wrong.
    private mutating func migrate() {
        // 1.1 listed X as com.x.twitter, which never matched the real app.
        if let i = apps.firstIndex(where: { $0.id == AppConfig.oldXBundleID }) {
            if apps.contains(where: { $0.id == AppConfig.xBundleID }) {
                apps.remove(at: i)
            } else {
                apps[i].id = AppConfig.xBundleID
            }
        }
        // Threads moved to threads.com.
        if let i = sites.firstIndex(where: { $0.id == "threads.net" }), !sites[i].domains.contains("threads.com") {
            sites[i].domains.append("threads.com")
        }
    }
}

/// One pause screen, and what happened after it.
struct FrictionEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var itemID: String
    var name: String
    var kind: FrictionKind
    var reason: String?
    /// False when the person closed it instead of opening.
    var opened: Bool
}

/// Focus hours turned on or off by hand, from the popover or Shortcuts.
struct FocusOverride: Codable, Hashable {
    var on: Bool
    /// Nil means until it is turned off again.
    var until: Date?
}

/// State that is not a setting: pauses and focus switches.
struct RuntimeState: Codable {
    var pausedUntil: Date?
    var focusOverride: FocusOverride?
    /// Set by a macOS Focus filter while that Focus is on.
    var focusFilter: FocusMode?
}

struct Persisted: Codable {
    var settings: AppSettings
    var days: [String: DayRecord]
    var log: [FrictionEntry]?
    var state: RuntimeState?
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
    case focus(name: String, until: Date?)

    var title: String {
        switch self {
        case .overall: return "Daily limit reached"
        case .item(let name, _, _): return "That's enough \(name)"
        case .focus(let name, _): return "\(name) can wait"
        }
    }

    var detail: String {
        switch self {
        case .overall(let used, let limit):
            return "\(Fmt.long(used)) on tracked sites and apps today. Your limit is \(Fmt.long(limit))."
        case .item(let name, let used, let limit):
            return "\(Fmt.long(used)) on \(name) today. The limit for it is \(Fmt.long(limit))."
        case .focus(_, let until):
            if let until { return "Focus hours run until \(Fmt.time(until))." }
            return "Focus hours are on."
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
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
    /// "4:30 PM", or "Tue 4:30 PM" when it is not today.
    static func time(_ date: Date) -> String {
        let t = timeFormatter.string(from: date)
        if Calendar.current.isDateInToday(date) { return t }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow at \(t)" }
        let day = DateFormatter()
        day.setLocalizedDateFormatFromTemplate("EEE")
        return "\(day.string(from: date)) \(t)"
    }
}
