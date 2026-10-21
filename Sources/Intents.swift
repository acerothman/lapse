import AppIntents
import Foundation

/// Shortcuts and the macOS Focus filter. They read and write the same store as the menu bar app.
enum LapseActions {
    @MainActor
    static func startSession() -> String {
        let store = Store.shared
        if store.activeSession != nil { return "A session is already running." }
        store.startSession(fromSystemFocus: false)
        return "Session started."
    }

    @MainActor
    static func requestEndSession() -> String {
        let store = Store.shared
        guard store.activeSession != nil else { return "No session is running." }
        store.requestEndEarly()
        return "Confirm to end the session."
    }

    @MainActor
    static func setPaused(_ paused: Bool) {
        Store.shared.settings.trackingPaused = paused
    }

    @MainActor
    static func setDailyLimit(minutes: Int) {
        Store.shared.settings.dailyLimitMinutes = min(480, max(15, minutes))
    }

    @MainActor
    static func setLimit(minutes: Int, site: String) -> String {
        let clean = site.trimmingCharacters(in: .whitespacesAndNewlines)
        let clamped = min(480, max(15, minutes))
        if clean.isEmpty {
            setDailyLimit(minutes: clamped)
            return "Daily limit is now \(Fmt.long(clamped * 60))."
        }
        let store = Store.shared
        if let index = store.settings.sites.firstIndex(where: {
            $0.name.compare(clean, options: .caseInsensitive) == .orderedSame || $0.id.compare(clean, options: .caseInsensitive) == .orderedSame
        }) {
            store.settings.sites[index].dailyLimitMinutes = clamped
            return "\(store.settings.sites[index].name) is now \(Fmt.long(clamped * 60))."
        }
        if let index = store.settings.apps.firstIndex(where: {
            $0.name.compare(clean, options: .caseInsensitive) == .orderedSame
        }) {
            store.settings.apps[index].dailyLimitMinutes = clamped
            return "\(store.settings.apps[index].name) is now \(Fmt.long(clamped * 60))."
        }
        return "No site or app named \(clean)."
    }
}

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a session"
    static var description = IntentDescription("Start a focus session and block the apps and sites you picked.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { LapseActions.startSession() }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StopFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "End a session"
    static var description = IntentDescription("Ask before ending the focus. A break ends only after you confirm.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { LapseActions.requestEndSession() }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct PauseTrackingIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause tracking"
    static var description = IntentDescription("Stop counting until you resume.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { LapseActions.setPaused(true) }
        return .result(dialog: "Tracking is paused.")
    }
}

struct ResumeTrackingIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume tracking"
    static var description = IntentDescription("Start counting again.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { LapseActions.setPaused(false) }
        return .result(dialog: "Tracking is on.")
    }
}

struct TodayTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Today's time"
    static var description = IntentDescription("How much time Lapse has counted today.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await MainActor.run { Fmt.long(Store.shared.todayTotal) }
        return .result(dialog: "\(text) today.")
    }
}

struct SetLimitIntent: AppIntent {
    static var title: LocalizedStringResource = "Set a limit"
    static var description = IntentDescription("Change the daily limit, or the limit for one site or app.")
    static var openAppWhenRun = true

    @Parameter(title: "Minutes")
    var minutes: Int

    @Parameter(title: "Site or app", default: "")
    var site: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { LapseActions.setLimit(minutes: minutes, site: site) }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

enum FocusFilterRule: String, AppEnum {
    case session
    case stricter
    case block

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rule")
    static var caseDisplayRepresentations: [FocusFilterRule: DisplayRepresentation] = [
        .session: "Start a session",
        .stricter: "Stricter limits",
        .block: "Block outright"
    ]
}

/// Starts a session, or turns tracking rules on, while a Focus is on.
struct LapseFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Lapse"
    static var description = IntentDescription("Start a Lapse session with this Focus, or turn on tracking rules.")

    @Parameter(title: "While this Focus is on")
    var rule: FocusFilterRule

    var displayRepresentation: DisplayRepresentation {
        switch rule {
        case .session:
            return DisplayRepresentation(title: "Lapse", subtitle: "Start a session")
        case .stricter:
            return DisplayRepresentation(title: "Lapse", subtitle: "Stricter limits")
        case .block:
            return DisplayRepresentation(title: "Lapse", subtitle: "Block outright")
        }
    }

    var appContext: FocusFilterAppContext {
        FocusFilterAppContext(notificationFilterPredicate: nil)
    }

    func perform() async throws -> some IntentResult {
        let rule = self.rule
        await MainActor.run { FocusBridge.apply(rule: rule) }
        return .result()
    }
}

enum FocusBridge {
    @MainActor
    static func apply(rule: FocusFilterRule?) {
        let store = Store.shared
        guard let rule else {
            let startedByFocus = store.activeSession?.fromSystemFocus == true
            store.setSystemFocus(active: false, mode: .stricter)
            if startedByFocus { store.endSession(reason: nil) }
            return
        }
        switch rule {
        case .session:
            store.setSystemFocus(active: true, mode: .stricter)
            if store.activeSession == nil {
                store.startSession(fromSystemFocus: true)
            }
        case .stricter:
            store.setSystemFocus(active: true, mode: .stricter)
        case .block:
            store.setSystemFocus(active: true, mode: .block)
        }
    }

    static func refresh() async {
        do {
            let filter = try await LapseFocusFilter.current
            let rule = filter.rule
            await MainActor.run { apply(rule: rule) }
        } catch {
            await MainActor.run { apply(rule: nil) }
        }
    }
}

struct LapseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(), phrases: ["Start a session in \(\.applicationName)"],
                    shortTitle: "Start a session", systemImageName: "timer")
        AppShortcut(intent: StopFocusIntent(), phrases: ["End a session in \(\.applicationName)"],
                    shortTitle: "End a session", systemImageName: "stop.circle")
        AppShortcut(intent: PauseTrackingIntent(), phrases: ["Pause tracking in \(\.applicationName)"],
                    shortTitle: "Pause tracking", systemImageName: "pause")
        AppShortcut(intent: ResumeTrackingIntent(), phrases: ["Resume tracking in \(\.applicationName)"],
                    shortTitle: "Resume tracking", systemImageName: "play")
        AppShortcut(intent: TodayTimeIntent(), phrases: ["Today's time in \(\.applicationName)"],
                    shortTitle: "Today's time", systemImageName: "clock")
        AppShortcut(intent: SetLimitIntent(), phrases: ["Set a limit in \(\.applicationName)"],
                    shortTitle: "Set a limit", systemImageName: "slider.horizontal.3")
    }
}
