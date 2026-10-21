import Foundation

/// Which URL paths count when a site is set to the feed only.
enum FeedRules {
    static func supports(siteID: String) -> Bool {
        switch siteID {
        case "x.com", "reddit.com", "youtube.com", "instagram.com": return true
        default: return false
        }
    }

    static func isFeed(siteID: String, url: URL) -> Bool {
        let parts = url.path.lowercased().split(separator: "/").map(String.init)
        switch siteID {
        case "x.com": return x(parts)
        case "reddit.com": return reddit(parts)
        case "youtube.com": return youtube(parts, host: url.host?.lowercased() ?? "")
        case "instagram.com": return instagram(parts)
        default: return true
        }
    }

    /// Home and For You. Both live at /home. Not messages, compose, notifications, or settings.
    private static func x(_ parts: [String]) -> Bool {
        if parts.isEmpty { return true }
        return parts == ["home"]
    }

    /// The home feed and a subreddit listing. Not comments, messages, or the submit page.
    private static func reddit(_ parts: [String]) -> Bool {
        if parts.isEmpty { return true }
        guard parts.first == "r", parts.count >= 2 else { return false }
        if parts.count == 2 { return true }
        if parts.count == 3 {
            return ["hot", "new", "top", "rising", "best"].contains(parts[2])
        }
        return false
    }

    /// Home and Shorts. A youtu.be link is always a video.
    private static func youtube(_ parts: [String], host: String) -> Bool {
        if host == "youtu.be" || host.hasSuffix(".youtu.be") { return false }
        if parts.isEmpty { return true }
        return parts[0] == "shorts"
    }

    /// The main feed only. Not DMs, a post, reels, or account pages.
    private static func instagram(_ parts: [String]) -> Bool {
        parts.isEmpty
    }
}
