import Foundation

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

    func matches(host: String) -> Bool {
        let h = host.lowercased()
        return domains.contains { d in h == d || h.hasSuffix("." + d) }
    }

    static let defaults: [SiteConfig] = [
        SiteConfig(id: "x.com", name: "X", domains: ["x.com", "twitter.com"], enabled: true, colorHex: "#000000", icon: "icon-x"),
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

    static let defaults: [AppConfig] = [
        AppConfig(id: "com.x.twitter", name: "X", enabled: false),
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
}

struct Persisted: Codable {
    var settings: AppSettings
    var days: [String: DayRecord]
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
}
