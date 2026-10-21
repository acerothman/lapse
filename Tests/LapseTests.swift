import Foundation

// Plain checks for the parts of Lapse that don't need a screen: feed rules, limits,
// focus hours, pause screens and reading old data files. Run with scripts/test.sh.

private var failures = 0
private var passed = 0

private func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        passed += 1
    } else {
        failures += 1
        print("FAIL line \(line): \(message)")
    }
}

private func url(_ s: String) -> URL { URL(string: s)! }

@main
@MainActor
enum LapseTests {
    static func main() {
        feedRules()
        decoding()
        focusAndLimits()
        friction()
        links()
        print(failures == 0 ? "All \(passed) checks passed." : "\(failures) of \(passed + failures) checks failed.")
        exit(failures == 0 ? 0 : 1)
    }

    static func feedRules() {
        let feed: [(String, String)] = [
            ("x.com", "https://x.com/home"),
            ("x.com", "https://x.com/explore/tabs/for-you"),
            ("reddit.com", "https://www.reddit.com/"),
            ("reddit.com", "https://www.reddit.com/r/popular/"),
            ("reddit.com", "https://old.reddit.com/r/swift/top/?t=day"),
            ("reddit.com", "https://www.reddit.com/best/"),
            ("youtube.com", "https://www.youtube.com/"),
            ("youtube.com", "https://www.youtube.com/shorts/abc123"),
            ("instagram.com", "https://www.instagram.com/"),
            ("instagram.com", "https://www.instagram.com/reels/C1x2y3/"),
            ("instagram.com", "https://www.instagram.com/explore/"),
            ("tiktok.com", "https://www.tiktok.com/foryou"),
            ("facebook.com", "https://www.facebook.com/"),
            ("linkedin.com", "https://www.linkedin.com/feed/"),
            ("threads.net", "https://www.threads.com/"),
        ]
        for (site, address) in feed {
            check(FeedRules.isFeed(siteID: site, url: url(address)), "\(address) should count as feed")
        }
        let notFeed: [(String, String)] = [
            ("x.com", "https://x.com/messages"),
            ("x.com", "https://x.com/i/chat/123"),
            ("x.com", "https://x.com/compose/post"),
            ("x.com", "https://x.com/notifications"),
            ("x.com", "https://x.com/settings/account"),
            ("x.com", "https://x.com/someone/status/1234"),
            ("reddit.com", "https://www.reddit.com/r/swift/comments/abc/title/"),
            ("reddit.com", "https://www.reddit.com/message/inbox/"),
            ("reddit.com", "https://www.reddit.com/settings/"),
            ("reddit.com", "https://www.reddit.com/r/swift/submit"),
            ("youtube.com", "https://www.youtube.com/watch?v=abc"),
            ("youtube.com", "https://www.youtube.com/@channel"),
            ("instagram.com", "https://www.instagram.com/direct/inbox/"),
            ("instagram.com", "https://www.instagram.com/accounts/edit/"),
            ("instagram.com", "https://www.instagram.com/someone/"),
            ("tiktok.com", "https://www.tiktok.com/messages"),
            ("facebook.com", "https://www.facebook.com/messages/t/1"),
            ("linkedin.com", "https://www.linkedin.com/messaging/"),
            ("threads.net", "https://www.threads.com/activity"),
        ]
        for (site, address) in notFeed {
            check(!FeedRules.isFeed(siteID: site, url: url(address)), "\(address) should not count as feed")
        }
        check(FeedRules.isFeed(siteID: "example.com", url: url("https://example.com/anything")),
              "sites without rules count everywhere")
    }

    static func decoding() {
        // A 1.1 data file: no feedOnly, no friction, the wrong X bundle id, threads.net only.
        let old = """
        {"settings":{"dailyLimitMinutes":60,"idleThresholdSeconds":60,"notificationsEnabled":true,
        "softBlockEnabled":true,"didFinishOnboarding":true,
        "sites":[{"id":"x.com","name":"X","domains":["x.com","twitter.com"],"enabled":true,"colorHex":"#000000","icon":"icon-x"},
        {"id":"reddit.com","name":"Reddit","domains":["reddit.com"],"enabled":true,"colorHex":"#FF4500","icon":"icon-reddit","dailyLimitMinutes":20},
        {"id":"threads.net","name":"Threads","domains":["threads.net"],"enabled":false,"colorHex":"#000000","icon":"icon-threads"}],
        "apps":[{"id":"com.x.twitter","name":"X","enabled":true}],
        "focus":{"enabled":false,"days":[false,true,true,true,true,true,false],"startMinutes":540,"endMinutes":1020,"mode":"stricter","dailyLimitMinutes":30}},
        "days":{"2026-10-19":{"seconds":{"x.com":600},"visits":{"x.com":3},"notifiedWarning":false,"notifiedLimit":false}}}
        """
        guard let p = try? JSONDecoder().decode(Persisted.self, from: Data(old.utf8)) else {
            check(false, "1.1 file should decode")
            return
        }
        let s = p.settings
        check(s.dailyLimitMinutes == 60, "keeps the daily limit")
        check(s.sites.first { $0.id == "x.com" }?.feedOnly == true, "X turns on feed-only after the update")
        check(s.sites.first { $0.id == "reddit.com" }?.feedOnly == false, "other sites stay off feed-only")
        check(s.sites.first { $0.id == "reddit.com" }?.dailyLimitMinutes == 20, "keeps per-site limits")
        check(s.sites.first { $0.id == "reddit.com" }?.friction.kind == .off, "friction starts off")
        check(s.apps.first?.id == AppConfig.xBundleID, "X app id moves to com.atebits.Tweetie2")
        check(s.apps.first?.enabled == true, "X app keeps its switch")
        check(s.sites.first { $0.id == "threads.net" }?.domains.contains("threads.com") == true, "Threads gains threads.com")
        check(p.log == nil && p.state == nil, "no log or state in old files")
        check(p.days["2026-10-19"]?.seconds["x.com"] == 600, "keeps day records")

        // Round trip of new fields.
        var site = SiteConfig.defaults[0]
        site.friction = FrictionSettings(kind: .reason, seconds: 20, trigger: .focusHours)
        site.feedOnly = false
        let data = try! JSONEncoder().encode(site)
        let back = try! JSONDecoder().decode(SiteConfig.self, from: data)
        check(back.friction == site.friction && back.feedOnly == false, "friction and feed-only round trip")

        // Fresh install defaults.
        let fresh = AppSettings()
        check(fresh.sites.first { $0.id == "x.com" }?.feedOnly == true, "X is feed-only by default")
        check(fresh.apps.contains { $0.id == "com.atebits.Tweetie2" }, "X app uses the iOS bundle id")
    }

    static func focusAndLimits() {
        let store = Store.shared
        var settings = AppSettings()
        settings.dailyLimitMinutes = 60
        settings.focus.enabled = false
        settings.focus.mode = .stricter
        settings.focus.dailyLimitMinutes = 20
        store.replaceAll(settings: settings, days: [:], log: [], state: RuntimeState())

        check(!store.isFocusHours(), "no focus without a schedule")
        check(store.overallLimitSeconds() == 3600, "daily limit applies")

        store.startFocus(minutes: 30)
        check(store.isFocusHours(), "manual focus turns on")
        check(store.focusSource == .manual, "source is manual")
        check(store.overallLimitSeconds() == 1200, "focus limit applies in stricter mode")
        if let end = store.focusEnds() {
            check(abs(end.timeIntervalSinceNow - 1800) < 5, "manual focus ends in 30 minutes")
        } else {
            check(false, "manual focus has an end")
        }
        store.stopFocus()
        check(!store.isFocusHours(), "stop turns manual focus off")

        store.startFocus(minutes: nil)
        check(store.isFocusHours() && store.focusEnds() == nil, "open-ended focus has no end")
        store.stopFocus()

        // Focus filter on, then off.
        store.applyFocusFilter(.block)
        check(store.isFocusHours() && store.focusMode == .block, "focus filter turns on block mode")
        check(store.overallLimitSeconds() == 0, "block mode means zero")
        store.stopFocus()
        check(!store.isFocusHours(), "manual stop beats the filter")
        store.applyFocusFilter(nil)
        check(!store.isFocusHours() && store.state.focusOverride == nil, "filter off clears the stop")
        store.applyFocusFilter(.stricter)
        check(store.isFocusHours() && store.focusMode == .stricter, "filter back on")
        store.applyFocusFilter(nil)

        // Schedule covering all day today, then stopped by hand.
        var s2 = store.settings
        s2.focus.enabled = true
        s2.focus.days = Array(repeating: true, count: 7)
        s2.focus.startMinutes = 0
        s2.focus.endMinutes = 0
        store.settings = s2
        check(store.scheduleSaysFocus(), "all-day schedule is on")
        store.stopFocus()
        check(!store.isFocusHours(), "stopping a scheduled window works")
        store.replaceAll(settings: settings, days: [:], log: [], state: RuntimeState())

        // Overnight schedule: 22:00 to 06:00, Mondays only. Tuesday 02:00 belongs to Monday.
        var s3 = settings
        s3.focus.enabled = true
        s3.focus.days = [false, true, false, false, false, false, false]
        s3.focus.startMinutes = 22 * 60
        s3.focus.endMinutes = 6 * 60
        store.settings = s3
        let cal = Calendar.current
        var monday = DateComponents()
        monday.year = 2026; monday.month = 10; monday.day = 19; monday.hour = 23
        var tuesday = DateComponents()
        tuesday.year = 2026; tuesday.month = 10; tuesday.day = 20; tuesday.hour = 2
        var tuesdayLate = DateComponents()
        tuesdayLate.year = 2026; tuesdayLate.month = 10; tuesdayLate.day = 20; tuesdayLate.hour = 23
        check(store.scheduleSaysFocus(at: cal.date(from: monday)!), "Monday 23:00 is on")
        check(store.scheduleSaysFocus(at: cal.date(from: tuesday)!), "Tuesday 02:00 is on, from Monday night")
        check(!store.scheduleSaysFocus(at: cal.date(from: tuesdayLate)!), "Tuesday 23:00 is off")
        store.replaceAll(settings: settings, days: [:], log: [], state: RuntimeState())

        // Pause.
        store.pause(minutes: 15)
        check(store.isPaused, "pause works")
        check(store.softBlockReason(currentID: "x.com") == nil, "no limit screen while paused")
        store.resume()
        check(!store.isPaused, "resume works")
        store.pause(minutes: nil)
        check(store.pausedUntil == .distantFuture, "pause until resumed")
        store.resume()

        // Item limits.
        check(store.setItemLimit("reddit.com", minutes: 25), "set a site limit")
        check(store.itemLimitSeconds(for: "reddit.com") == 1500, "site limit reads back")
        check(store.setItemLimit("reddit.com", minutes: 0), "clear a site limit")
        check(store.itemLimitSeconds(for: "reddit.com") == nil, "site limit cleared")
        check(!store.setItemLimit("nope.example", minutes: 5), "unknown id is refused")

        // Feed-only lookups through the store.
        check(store.site(for: url("https://x.com/home"))?.id == "x.com", "X home counts")
        check(store.site(for: url("https://x.com/messages")) == nil, "X DMs don't count with feed-only")
        if let i = store.settings.sites.firstIndex(where: { $0.id == "x.com" }) { store.settings.sites[i].feedOnly = false }
        check(store.site(for: url("https://x.com/messages"))?.id == "x.com", "X DMs count with feed-only off")
        check(store.site(for: url("https://old.reddit.com/r/swift/comments/x/y/"))?.id == "reddit.com",
              "Reddit threads count while feed-only is off")
    }

    @MainActor
    static func links() {
        let store = Store.shared
        store.replaceAll(settings: AppSettings(), days: [:], log: [], state: RuntimeState())
        check(Links.handle(url("lapse://pause?minutes=30"), store: store) && store.isPaused, "pause link")
        check(Links.handle(url("lapse://resume"), store: store) && !store.isPaused, "resume link")
        check(Links.handle(url("lapse://focus/start"), store: store) && store.isFocusHours() && store.focusEnds() == nil,
              "open-ended focus link")
        check(Links.handle(url("lapse://focus/stop"), store: store) && !store.isFocusHours(), "focus stop link")
        check(Links.handle(url("lapse://limit?minutes=45"), store: store) && store.settings.dailyLimitMinutes == 45, "daily limit link")
        check(Links.handle(url("lapse://limit?minutes=10&site=Reddit"), store: store)
              && store.settings.sites.first { $0.id == "reddit.com" }?.dailyLimitMinutes == 10, "site limit link by name")
        check(Links.handle(url("lapse://limit?minutes=0&site=reddit.com"), store: store)
              && store.settings.sites.first { $0.id == "reddit.com" }?.dailyLimitMinutes == nil, "zero clears a site limit")
        check(!Links.handle(url("lapse://limit?minutes=10&site=nowhere.example"), store: store), "unknown site is refused")
        check(!Links.handle(url("lapse://nonsense"), store: store), "unknown link is refused")
        check(!Links.handle(url("https://x.com/home"), store: store), "other schemes are ignored")
    }

    static func friction() {
        let store = Store.shared
        var settings = AppSettings()
        settings.dailyLimitMinutes = 60
        if let i = settings.sites.firstIndex(where: { $0.id == "x.com" }) {
            settings.sites[i].friction = FrictionSettings(kind: .countdown, seconds: 10, trigger: .always)
        }
        if let i = settings.sites.firstIndex(where: { $0.id == "reddit.com" }) {
            settings.sites[i].friction = FrictionSettings(kind: .reason, seconds: 10, trigger: .overLimit)
        }
        if let i = settings.sites.firstIndex(where: { $0.id == "youtube.com" }) {
            settings.sites[i].friction = FrictionSettings(kind: .countdown, seconds: 5, trigger: .focusHours)
        }
        store.replaceAll(settings: settings, days: [:], log: [], state: RuntimeState())

        check(store.frictionNeeded(for: "x.com")?.kind == .countdown, "X always pauses")
        check(store.frictionNeeded(for: "reddit.com") == nil, "Reddit waits for a limit")
        check(store.frictionNeeded(for: "youtube.com") == nil, "YouTube waits for focus hours")
        check(store.frictionNeeded(for: "tiktok.com") == nil, "TikTok has no pause screen")

        store.add(seconds: 3600, to: "instagram.com")
        check(store.frictionNeeded(for: "reddit.com")?.kind == .reason, "Reddit pauses past the overall limit")
        store.startFocus(minutes: 10)
        check(store.frictionNeeded(for: "youtube.com")?.seconds == 5, "YouTube pauses in focus hours")
        store.stopFocus()

        store.record(FrictionEntry(date: Date(), itemID: "reddit.com", name: "Reddit", kind: .reason, reason: "Recipe", opened: true))
        store.record(FrictionEntry(date: Date(), itemID: "reddit.com", name: "Reddit", kind: .reason, reason: nil, opened: false))
        check(store.lastReason(for: "reddit.com") == "Recipe", "last typed reason is remembered")
        check(store.log.count == 2, "both entries logged")
        store.clearLog()
        check(store.log.isEmpty, "log clears")
    }
}
