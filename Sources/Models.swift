import Foundation

struct SiteConfig: Codable, Identifiable, Hashable {
    var id: String            // primary domain, e.g. "x.com"
    var name: String
    var domains: [String]     // all hosts that count for this site
    var enabled: Bool
    var colorHex: String
    var icon: String?         // resource name without extension, e.g. "icon-x"

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

struct DayRecord: Codable {
    var seconds: [String: Int] = [:]   // site id -> seconds
    var visits: [String: Int] = [:]    // site id -> visit count
    var notifiedWarning = false
    var notifiedLimit = false

    var total: Int { seconds.values.reduce(0, +) }
}

struct AppSettings: Codable {
    var dailyLimitMinutes: Int = 90
    var idleThresholdSeconds: Int = 60
    var notificationsEnabled: Bool = true
    var sites: [SiteConfig] = SiteConfig.defaults
    /// False until the welcome window is finished. Missing in older files, so decode it by hand.
    var didFinishOnboarding: Bool = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case dailyLimitMinutes, idleThresholdSeconds, notificationsEnabled, sites, didFinishOnboarding
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes) ?? 90
        idleThresholdSeconds = try c.decodeIfPresent(Int.self, forKey: .idleThresholdSeconds) ?? 60
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        sites = try c.decodeIfPresent([SiteConfig].self, forKey: .sites) ?? SiteConfig.defaults
        didFinishOnboarding = try c.decodeIfPresent(Bool.self, forKey: .didFinishOnboarding) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        try c.encode(idleThresholdSeconds, forKey: .idleThresholdSeconds)
        try c.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try c.encode(sites, forKey: .sites)
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
