import AppIntents
import Foundation

// Shortcuts actions and the Focus filter. build.sh runs Xcode's metadata extractor over
// these so Shortcuts and System Settings can find them.

// MARK: - Sites and apps

struct TrackedItemEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Site or App"
    static var defaultQuery = TrackedItemQuery()

    var id: String
    var name: String
    var detail: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(detail)")
    }

    @MainActor
    static func all() -> [TrackedItemEntity] {
        let settings = Store.shared.settings
        return settings.sites.map { TrackedItemEntity(id: $0.id, name: $0.name, detail: $0.id) }
            + settings.apps.map { TrackedItemEntity(id: $0.id, name: $0.name, detail: "App") }
    }
}

struct TrackedItemQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TrackedItemEntity] {
        await MainActor.run { TrackedItemEntity.all().filter { identifiers.contains($0.id) } }
    }

    func suggestedEntities() async throws -> [TrackedItemEntity] {
        await MainActor.run { TrackedItemEntity.all() }
    }
}

// MARK: - Focus hours

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Focus Hours"
    static var description = IntentDescription("Turns on Lapse focus hours now, for a number of minutes or until you end them.")

    @Parameter(title: "Minutes", description: "Leave empty to keep focus hours on until you end them.")
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Start focus hours for \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        store.startFocus(minutes: minutes.map { max(1, $0) })
        let text = store.focusEnds().map { "Focus hours are on until \(Fmt.time($0))." }
            ?? "Focus hours are on until you end them."
        return .result(dialog: "\(text)")
    }
}

struct StopFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "End Focus Hours"
    static var description = IntentDescription("Turns off Lapse focus hours. A scheduled window stays off until it would have ended.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        let wasOn = store.isFocusHours()
        store.stopFocus()
        return .result(dialog: "\(wasOn ? "Focus hours are off." : "Focus hours weren't on.")")
    }
}

// MARK: - Pause

struct PauseTrackingIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Tracking"
    static var description = IntentDescription("Stops counting time, and stops limit and pause screens, for a number of minutes or until you resume.")

    @Parameter(title: "Minutes", description: "Leave empty to pause until you resume.")
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Pause tracking for \(\.$minutes) minutes")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        store.pause(minutes: minutes.map { max(1, $0) })
        let text: String
        if let until = store.pausedUntil, until != .distantFuture {
            text = "Lapse is paused until \(Fmt.time(until))."
        } else {
            text = "Lapse is paused until you resume it."
        }
        return .result(dialog: "\(text)")
    }
}

struct ResumeTrackingIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Tracking"
    static var description = IntentDescription("Starts counting time again after a pause.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        Store.shared.resume()
        return .result(dialog: "Lapse is counting again.")
    }
}

// MARK: - Today

struct GetTodayTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today's Time"
    static var description = IntentDescription("Minutes spent today on all tracked sites and apps, or on one of them.")

    @Parameter(title: "Site or App", description: "Leave empty for the total.")
    var item: TrackedItemEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Get today's time on \(\.$item)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let store = Store.shared
        let text: String
        let seconds: Int
        if let item {
            seconds = store.seconds(for: item.id)
            if let cap = store.itemLimitSeconds(for: item.id), cap > 0 {
                let rest = cap - seconds
                text = "\(Fmt.long(seconds)) on \(item.name) today. " + (rest > 0 ? "\(Fmt.long(rest)) left." : "That's past its limit.")
            } else {
                text = "\(Fmt.long(seconds)) on \(item.name) today."
            }
        } else {
            seconds = store.todayTotal
            let limit = store.limitSeconds
            if limit > 0 {
                let rest = limit - seconds
                text = "\(Fmt.long(seconds)) today. " + (rest > 0 ? "\(Fmt.long(rest)) left of \(Fmt.long(limit))." : "That's past your \(Fmt.long(limit)) limit.")
            } else {
                text = "\(Fmt.long(seconds)) today."
            }
        }
        return .result(value: seconds / 60, dialog: "\(text)")
    }
}

// MARK: - Limits

struct SetLimitIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Limit"
    static var description = IntentDescription("Changes the daily limit, or the limit for one site or app. Use 0 minutes to remove a site or app limit.")

    @Parameter(title: "Minutes")
    var minutes: Int

    @Parameter(title: "Site or App", description: "Leave empty to change the overall daily limit.")
    var item: TrackedItemEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Set the limit to \(\.$minutes) minutes") {
            \.$item
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        if let item {
            store.setItemLimit(item.id, minutes: minutes)
            let text = minutes > 0 ? "\(item.name) now has a \(Fmt.long(minutes * 60)) limit." : "\(item.name) has no limit of its own now."
            return .result(dialog: "\(text)")
        }
        let value = min(max(minutes, 1), 24 * 60)
        store.settings.dailyLimitMinutes = value
        return .result(dialog: "Your daily limit is \(Fmt.long(value * 60)) now.")
    }
}

// MARK: - Shortcuts app and Spotlight

struct LapseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartFocusIntent(),
                    phrases: ["Start focus hours in \(.applicationName)", "Start \(.applicationName) focus hours"])
        AppShortcut(intent: StopFocusIntent(),
                    phrases: ["End focus hours in \(.applicationName)", "Stop \(.applicationName) focus hours"])
        AppShortcut(intent: PauseTrackingIntent(),
                    phrases: ["Pause \(.applicationName)", "Pause tracking in \(.applicationName)"])
        AppShortcut(intent: ResumeTrackingIntent(),
                    phrases: ["Resume \(.applicationName)", "Resume tracking in \(.applicationName)"])
        AppShortcut(intent: GetTodayTimeIntent(),
                    phrases: ["How much time today in \(.applicationName)", "Check \(.applicationName)"])
    }
}

// MARK: - Focus filter

enum FocusFilterRules: String, AppEnum {
    case off
    case stricter
    case block

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Focus Hours"
    static var caseDisplayRepresentations: [FocusFilterRules: DisplayRepresentation] = [
        .off: "Off",
        .stricter: "On, with stricter limits",
        .block: "On, blocking sites and apps",
    ]

    var mode: FocusMode? {
        switch self {
        case .off: return nil
        case .stricter: return .stricter
        case .block: return .block
        }
    }
}

/// Turns Lapse focus hours on with a macOS Focus. When that Focus ends, the system calls
/// perform() again with the default value, which is off.
struct LapseFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Set Lapse Focus Hours"
    static var description: IntentDescription? = IntentDescription("Turns on Lapse focus hours while this Focus is on.")

    // Must default to off: the system sends the default when the Focus ends.
    @Parameter(title: "Focus Hours", default: .off)
    var rules: FocusFilterRules

    var displayRepresentation: DisplayRepresentation {
        switch rules {
        case .off: return "Focus hours off"
        case .stricter: return "Stricter limits"
        case .block: return "Block sites and apps"
        }
    }

    static func suggestedFocusFilters(for context: FocusFilterSuggestionContext) async -> [LapseFocusFilter] {
        let stricter = LapseFocusFilter()
        stricter.rules = .stricter
        let block = LapseFocusFilter()
        block.rules = .block
        return [stricter, block]
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        Store.shared.applyFocusFilter(rules.mode)
        return .result()
    }

    /// Catches up after launch, since a Focus may have changed while Lapse was closed.
    @MainActor
    static func sync() async {
        guard let current = try? await LapseFocusFilter.current else { return }
        Store.shared.applyFocusFilter(current.rules.mode)
    }
}
