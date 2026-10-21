import Foundation

/// Which pages count as the feed on sites that have one. Decided from the URL path only.
/// Anything not listed here (DMs, posting, notifications, settings, profiles) does not count
/// while feed-only is on for that site.
enum FeedRules {
    struct Rule {
        /// One plain sentence for Settings.
        let summary: String
        /// Lowercased path components, without empty parts. Root is [].
        let isFeed: ([String]) -> Bool
    }

    static func rule(for siteID: String) -> Rule? { rules[siteID] }

    static func isFeed(siteID: String, url: URL) -> Bool {
        guard let rule = rules[siteID] else { return true }
        return rule.isFeed(components(of: url))
    }

    static func components(of url: URL) -> [String] {
        url.path.lowercased().split(separator: "/").map(String.init)
    }

    private static let redditListings: Set<String> = ["best", "hot", "new", "top", "rising", "controversial"]

    private static let rules: [String: Rule] = [
        "x.com": Rule(summary: "Home and Explore count. DMs, posting, notifications and settings don't.") { p in
            // Composing opens /compose/post on top of the timeline, so it drops out on its own.
            p.first == "home" || p.first == "explore"
        },
        "reddit.com": Rule(summary: "The front page and subreddit feeds count. Comment threads, chat, messages and settings don't.") { p in
            if p.isEmpty { return true }
            if p.count == 1 { return redditListings.contains(p[0]) }
            if p[0] == "r" {
                if p.count == 2 { return true }
                if p.count == 3 { return redditListings.contains(p[2]) }
            }
            return false
        },
        "youtube.com": Rule(summary: "Home and Shorts count. A video you open on purpose doesn't.") { p in
            p.isEmpty || p.first == "shorts"
        },
        "instagram.com": Rule(summary: "Home, Reels and Explore count. DMs, profiles and settings don't.") { p in
            p.isEmpty || p.first == "reels" || p.first == "explore"
        },
        "tiktok.com": Rule(summary: "For You, Following and Explore count. Messages, uploads and settings don't.") { p in
            p.isEmpty || ["foryou", "following", "explore"].contains(p[0])
        },
        "facebook.com": Rule(summary: "The news feed, Watch and Reels count. Messages, notifications and settings don't.") { p in
            p.isEmpty || ["home.php", "watch", "reel", "reels"].contains(p[0])
        },
        "linkedin.com": Rule(summary: "The feed counts. Messages, jobs, profiles and notifications don't.") { p in
            p.first == "feed"
        },
        "threads.net": Rule(summary: "The home feed counts. Activity, search and profiles don't.") { p in
            p.isEmpty
        },
    ]
}
