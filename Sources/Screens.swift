import SwiftUI
import Charts
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

enum SettingsPage: Hashable {
    case general, blocking, sessions, tracking
}

final class SettingsRouter: ObservableObject {
    @Published var tab: SettingsPage = .general
}

struct PopoverView: View {
    @ObservedObject var store: Store
    @ObservedObject var updates: UpdateCheck
    let openSettings: (SettingsPage) -> Void

    private var running: ActiveSession? { store.activeSession }
    private var onBreak: Bool {
        guard let phase = running?.phase else { return false }
        return phase != .focus
    }
    private var accent: Color { onBreak ? .lapseBreak : .lapseAccent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let version = updates.available {
                notice("Lapse \(version) is out", button: "Download", action: updates.openDownload)
                    .padding(.top, 12)
            }
            timerBlock
                .padding(.top, 18)
                .frame(maxWidth: .infinity)
            if running == nil {
                durationPicker
                    .padding(.top, 16)
                blockingRow
                    .padding(.top, 12)
                Button(action: { store.startSession(fromSystemFocus: false) }) {
                    Text("Start focus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(StartButtonStyle())
                .padding(.top, 12)
                hairline.padding(.vertical, 14)
                todayBlock
            } else if onBreak {
                Text("Apps are back.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
                Button("Skip break", action: store.skipBreak)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
            } else {
                HStack(spacing: 12) {
                    Button(running?.pausedRemaining == nil ? "Pause" : "Resume", action: store.togglePauseSession)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("End early", action: store.requestEndEarly)
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)
                hairline.padding(.vertical, 14)
                Text("Blocked \(running?.blockedAttempts ?? 0) attempts")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text("Lapse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Button(action: { openSettings(.general) }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
    }

    private var timerBlock: some View {
        VStack(spacing: 8) {
            Text(store.phaseTitle())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(Fmt.session(running == nil ? store.upcomingFocusMinutes() * 60 : store.remainingSeconds()))
                .font(.system(size: 56, weight: .light))
                .monospacedDigit()
                .tracking(-1)
                .foregroundStyle(.primary)
            if running != nil {
                UsageBar(fraction: store.sessionFraction(), height: 2, color: accent)
                    .frame(width: 160)
            }
            SessionDots(filled: store.filledDotCount(), total: store.dotCount(), color: accent)
            if running != nil {
                Text(store.sessionCaption())
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var durationPicker: some View {
        VStack(spacing: 8) {
            Picker("Length", selection: Binding(get: { store.settings.session.preset },
                                                 set: { store.selectPreset($0) })) {
                Text("25").tag(25)
                Text("50").tag(50)
                Text("Custom").tag(0)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if store.settings.session.preset == 0 {
                Stepper(value: Binding(get: { store.settings.session.customMinutes },
                                       set: { store.setCustomMinutes($0) }),
                        in: 5...180, step: 5) {
                    Text("\(store.settings.session.customMinutes) min")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var blockingRow: some View {
        let sites = store.enabledSites
        let apps = store.enabledApps
        let count = sites.count + apps.count
        return Button(action: { openSettings(.blocking) }) {
            HStack(spacing: 8) {
                Text(blockingTitle(count))
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: -4) {
                    ForEach(sites.prefix(4)) { site in
                        SiteIcon(site: site, favicon: store.favicons[site.id], size: 16)
                    }
                    if sites.count < 4 {
                        ForEach(apps.prefix(4 - sites.count)) { app in
                            AppIconView(image: store.appIcons[app.id], name: app.name, size: 16)
                        }
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var todayBlock: some View {
        let rows = store.topTargets(3)
        let peak = max(rows.map(\.seconds).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack {
                Text(Fmt.compact(store.todayTotal))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(store.todayFocusCount()) sessions")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(width: 72, alignment: .leading)
                    UsageBar(fraction: Double(row.seconds) / Double(peak),
                             height: 3,
                             color: index == 0 && row.seconds > 0 ? .lapseAccent : Color.primary.opacity(0.28))
                    Text(Fmt.compact(row.seconds))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }
        }
    }

    private var hairline: some View {
        Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)
    }

    private func blockingTitle(_ count: Int) -> String {
        switch count {
        case 0: return "Nothing blocked"
        case 1: return "Blocking 1 app or site"
        default: return "Blocking \(count) apps and sites"
        }
    }

    private func notice(_ title: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Button(button, action: action)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SessionDots: View {
    var filled: Int
    var total: Int
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? color : Color.primary.opacity(0.16))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

struct StartButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.lapseAccent.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

struct AppIconView: View {
    let image: NSImage?
    let name: String
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .controlBackgroundColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .tertiaryLabelColor))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

struct WeekChart: View {
    let week: [Store.WeekDay]
    let limitSeconds: Int

    var body: some View {
        let limitMin = Double(limitSeconds) / 60
        let maxMin = week.map { Double($0.seconds) / 60 }.max() ?? 0
        Chart {
            ForEach(week) { day in
                BarMark(x: .value("Day", day.label),
                        y: .value("Minutes", Double(day.seconds) / 60))
                    .foregroundStyle(color(for: day))
                    .cornerRadius(2)
            }
        }
        .chartYScale(domain: 0...max(limitMin * 1.12, maxMin * 1.05, 1))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel() }
        }
        .animation(.easeOut(duration: 0.35), value: week.map(\.seconds))
    }

    private func color(for day: Store.WeekDay) -> Color {
        if day.seconds > limitSeconds { return Color.lapseAccent }
        return day.isToday ? Color.primary : Color.primary.opacity(0.28)
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var router: SettingsRouter
    var showWelcome: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $router.tab) {
                Text("General").tag(SettingsPage.general)
                Text("Blocking").tag(SettingsPage.blocking)
                Text("Sessions").tag(SettingsPage.sessions)
                Text("Tracking").tag(SettingsPage.tracking)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            Group {
                switch router.tab {
                case .general:
                    GeneralSettings(store: store, showWelcome: showWelcome)
                case .blocking:
                    BlockingSettings(store: store)
                case .sessions:
                    SessionSettingsView(store: store)
                case .tracking:
                    TrackingSettings(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            for app in store.settings.apps { _ = store.icon(forBundleID: app.id) }
        }
    }
}

private struct GeneralSettings: View {
    @ObservedObject var store: Store
    var showWelcome: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                Toggle("Notifications", isOn: $store.settings.notificationsEnabled)
                Toggle("Pause tracking", isOn: $store.settings.trackingPaused)
            } header: {
                Text("General").sectionHeading()
            } footer: {
                Text("Notifications cover the daily limit and the change from focus to a break.")
            }
            Section {
                Button("Show welcome again", action: showWelcome)
            }
        }
        .formStyle(.grouped)
    }
}

private struct BlockingSettings: View {
    @ObservedObject var store: Store
    @State private var newDomain = ""

    var body: some View {
        Form {
            Section {
                ForEach($store.settings.sites) { $site in
                    Toggle(isOn: $site.enabled) {
                        HStack(spacing: 8) {
                            SiteIcon(site: site, favicon: store.favicons[site.id], size: 16)
                            Text(site.name)
                        }
                    }
                    .contextMenu {
                        Button("Remove \(site.name)", role: .destructive) {
                            let id = site.id
                            DispatchQueue.main.async { store.removeSite(id) }
                        }
                    }
                }
                ForEach($store.settings.apps) { $app in
                    Toggle(isOn: $app.enabled) {
                        HStack(spacing: 8) {
                            AppIconView(image: store.appIcons[app.id], name: app.name, size: 16)
                            Text(app.name)
                        }
                    }
                    .contextMenu {
                        Button("Remove \(app.name)", role: .destructive) {
                            let id = app.id
                            DispatchQueue.main.async { store.removeApp(id) }
                        }
                    }
                }
            } header: {
                Text("Blocked during focus").sectionHeading()
            } footer: {
                Text("Locked during a focus. Counted the rest of the time.")
            }
            Section {
                HStack {
                    TextField("Add a site, like news.ycombinator.com", text: $newDomain)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addSite)
                    Button("Add", action: addSite).disabled(newDomain.isEmpty)
                }
                Button("Add an app", action: addApp)
            }
        }
        .formStyle(.grouped)
    }

    private func addSite() {
        store.addSite(domain: newDomain)
        newDomain = ""
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a Mac app to block during focus."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addApp(at: url)
    }
}

private struct SessionSettingsView: View {
    @ObservedObject var store: Store

    var body: some View {
        Form {
            Section {
                Stepper(value: focusLength, in: 5...180, step: 5) {
                    valueRow("Focus length", "\(store.settings.session.focusMinutes) min")
                }
                Stepper(value: $store.settings.session.shortBreakMinutes, in: 1...30) {
                    valueRow("Short break", "\(store.settings.session.shortBreakMinutes) min")
                }
                Stepper(value: $store.settings.session.longBreakMinutes, in: 5...60, step: 5) {
                    valueRow("Long break", "\(store.settings.session.longBreakMinutes) min")
                }
                Stepper(value: $store.settings.session.roundsUntilLong, in: 2...8) {
                    valueRow("Long break every", "\(store.settings.session.roundsUntilLong)")
                }
            } header: {
                Text("Sessions").sectionHeading()
            }
            Section {
                Picker("During a focus", selection: $store.settings.session.hideApps) {
                    Text("Hide").tag(true)
                    Text("Quit").tag(false)
                }
            } footer: {
                Text("Hide leaves them open. Quit closes them.")
            }
            Section {
                valueRow("Streak", "\(store.focusStreak()) days")
                if store.sessionLog.isEmpty {
                    Text("No sessions yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.sessionLog.prefix(8)) { entry in
                        HStack {
                            Text(entry.completed ? "Finished" : "Ended early")
                            Spacer()
                            Text(entry.endedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                                .font(.system(size: 12))
                        }
                    }
                }
            } header: {
                Text("History").sectionHeading()
            }
        }
        .formStyle(.grouped)
    }

    private var focusLength: Binding<Int> {
        Binding(get: { store.settings.session.focusMinutes },
                set: { minutes in
                    var session = store.settings.session
                    session.focusMinutes = min(180, max(5, minutes))
                    if session.focusMinutes == 25 {
                        session.preset = 25
                    } else if session.focusMinutes == 50 {
                        session.preset = 50
                    } else {
                        session.preset = 0
                        session.customMinutes = session.focusMinutes
                    }
                    store.settings.session = session
                })
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrackingSettings: View {
    @ObservedObject var store: Store

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Daily limit")
                    Spacer()
                    Text(Fmt.long(store.settings.dailyLimitMinutes * 60))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: dailyLimit, in: 15...480, step: 15)
                Stepper(value: $store.settings.idleThresholdSeconds, in: 15...600, step: 15) {
                    HStack {
                        Text("Pause after idle")
                        Spacer()
                        Text("\(store.settings.idleThresholdSeconds) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Show a screen at the limit", isOn: $store.settings.softBlockEnabled)
            } header: {
                Text("Daily limit").sectionHeading()
            } footer: {
                Text("Snooze it, or turn it off for the day.")
            }

            Section {
                Toggle("Use focus hours", isOn: $store.settings.focus.enabled)
                if store.settings.focus.manualOn {
                    HStack {
                        Text("Focus hours are on now")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Stop") { store.settings.focus.manualOn = false }
                            .controlSize(.small)
                    }
                }
                if store.settings.focus.enabled {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { index in
                            dayButton(index)
                        }
                    }
                    HStack {
                        Text("From")
                        DatePicker("", selection: focusStart, displayedComponents: .hourAndMinute).labelsHidden()
                        Text("to")
                        DatePicker("", selection: focusEnd, displayedComponents: .hourAndMinute).labelsHidden()
                    }
                    Picker("During these hours", selection: $store.settings.focus.mode) {
                        Text("Stricter limits").tag(FocusMode.stricter)
                        Text("Block outright").tag(FocusMode.block)
                    }
                    if store.settings.focus.mode == .stricter {
                        Slider(value: focusLimit, in: 15...240, step: 15)
                        Text("Focus limit \(Fmt.long(store.settings.focus.dailyLimitMinutes * 60))")
                            .foregroundStyle(.secondary)
                    }
                }
                if store.systemFocusActive {
                    Text(store.systemFocusMode == .block ? "A Focus is blocking these." : "A Focus is using the stricter limit.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Focus hours").sectionHeading()
            } footer: {
                Text(store.settings.focus.mode == .block
                     ? "The screen comes up right away, unless you turned that screen off."
                     : "Outside a session, the limit drops to this during the window.")
            }

            Section {
                Picker("When", selection: $store.settings.frictionWhen) {
                    ForEach(FrictionWhen.allCases, id: \.self) { when in
                        Text(when.label).tag(when)
                    }
                }
                Picker("Pause", selection: $store.settings.frictionStyle) {
                    ForEach(FrictionStyle.allCases, id: \.self) { style in
                        Text(style.label).tag(style)
                    }
                }
                if store.settings.frictionStyle == .countdown {
                    Picker("Length", selection: $store.settings.frictionSeconds) {
                        ForEach([5, 10, 15, 30], id: \.self) { seconds in
                            Text("\(seconds) seconds").tag(seconds)
                        }
                    }
                }
            } header: {
                Text("Before opening").sectionHeading()
            } footer: {
                Text("This is also the hold before a focus ends early. Each site and app can use a different pause.")
            }

            Section {
                ForEach($store.settings.sites) { $site in
                    if site.supportsFeed {
                        Toggle("\(site.name) feed only", isOn: $site.feedOnly)
                        Text(feedCaption(site.id))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Feeds").sectionHeading()
            } footer: {
                Text("Feeds are counted outside a focus. A focus blocks the whole app or site.")
            }

            Section {
                ForEach($store.settings.sites) { $site in
                    if site.enabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.name)
                            limitMenus(daily: $site.dailyLimitMinutes, focus: $site.focusLimitMinutes)
                            pauseMenus(when: $site.frictionWhen, style: $site.frictionStyle, seconds: $site.frictionSeconds)
                        }
                    }
                }
                ForEach($store.settings.apps) { $app in
                    if app.enabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name)
                            limitMenus(daily: $app.dailyLimitMinutes, focus: $app.focusLimitMinutes)
                            pauseMenus(when: $app.frictionWhen, style: $app.frictionStyle, seconds: $app.frictionSeconds)
                        }
                    }
                }
            } header: {
                Text("Per app and site").sectionHeading()
            }

            Section {
                WeekChart(week: store.lastSevenDays(),
                          limitSeconds: max(store.settings.dailyLimitMinutes, 1) * 60)
                    .frame(height: 88)
            } header: {
                Text("This week").sectionHeading()
            }

            Section {
                Text("Shortcuts can start a session, pause tracking, read today's time, and change a limit. A Focus can start a session, or turn on stricter limits or a block.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Shortcuts").sectionHeading()
            }

            Section {
                if store.frictionNotes.isEmpty {
                    Text("Nothing logged yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.frictionNotes.prefix(12)) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(note.name)
                                Spacer()
                                Text(note.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Text(note.reason)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Why you opened them").sectionHeading()
            }
        }
        .formStyle(.grouped)
    }

    private var dailyLimit: Binding<Double> {
        Binding(get: { Double(store.settings.dailyLimitMinutes) },
                set: { store.settings.dailyLimitMinutes = Int($0) })
    }

    private var focusLimit: Binding<Double> {
        Binding(get: { Double(store.settings.focus.dailyLimitMinutes) },
                set: { store.settings.focus.dailyLimitMinutes = Int($0) })
    }

    private var focusStart: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: store.settings.focus.startMinutes) },
                set: { store.settings.focus.startMinutes = Self.minutes(from: $0) })
    }

    private var focusEnd: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: store.settings.focus.endMinutes) },
                set: { store.settings.focus.endMinutes = Self.minutes(from: $0) })
    }

    private static let dayLetters = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    private func dayButton(_ index: Int) -> some View {
        let on = store.settings.focus.days.indices.contains(index) && store.settings.focus.days[index]
        return Button(Self.dayLetters[index]) { toggleDay(index) }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: on ? .semibold : .regular))
            .frame(width: 28, height: 28)
            .foregroundStyle(on ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .background(Circle().fill(on ? Color.primary : Color.primary.opacity(0.08)))
    }

    private func toggleDay(_ index: Int) {
        guard store.settings.focus.days.indices.contains(index) else { return }
        var days = store.settings.focus.days
        days[index].toggle()
        store.settings.focus.days = days
    }

    private static func date(fromMinutes minutes: Int) -> Date {
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        parts.hour = minutes / 60
        parts.minute = minutes % 60
        return Calendar.current.date(from: parts) ?? Date()
    }

    private static func minutes(from date: Date) -> Int {
        let cal = Calendar.current
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }

    private func feedCaption(_ id: String) -> String {
        switch id {
        case "x.com": return "Home and For You. Not messages, a post you're writing, notifications, or settings."
        case "reddit.com": return "Home and subreddit feeds. Not comments, messages, or a post you're writing."
        case "youtube.com": return "Home and Shorts. Not a normal video."
        case "instagram.com": return "The feed. Not messages or settings."
        default: return "Only the main feed."
        }
    }

    private func limitMenus(daily: Binding<Int?>, focus: Binding<Int?>) -> some View {
        HStack(spacing: 12) {
            MinuteLimitMenu(minutes: daily, title: "Limit")
            if store.settings.focus.enabled && store.settings.focus.mode == .stricter {
                MinuteLimitMenu(minutes: focus, title: "Focus")
            }
        }
    }

    private func pauseMenus(when: Binding<FrictionWhen?>, style: Binding<FrictionStyle?>, seconds: Binding<Int?>) -> some View {
        HStack(spacing: 12) {
            Menu(when.wrappedValue?.label ?? "Pause: Default") {
                Button("Default") { when.wrappedValue = nil }
                ForEach(FrictionWhen.allCases, id: \.self) { value in
                    Button(value.label) { when.wrappedValue = value }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Menu(style.wrappedValue?.label ?? "Style: Default") {
                Button("Default") { style.wrappedValue = nil }
                ForEach(FrictionStyle.allCases, id: \.self) { value in
                    Button(value.label) { style.wrappedValue = value }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if (style.wrappedValue ?? store.settings.frictionStyle) == .countdown {
                Menu(seconds.wrappedValue.map { "\($0) seconds" } ?? "Length: Default") {
                    Button("Default") { seconds.wrappedValue = nil }
                    ForEach([5, 10, 15, 30], id: \.self) { value in
                        Button("\(value) seconds") { seconds.wrappedValue = value }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }
}

private extension Text {
    func sectionHeading() -> some View {
        font(.system(size: 11, weight: .medium)).textCase(nil)
    }
}

struct MinuteLimitMenu: View {
    @Binding var minutes: Int?
    var title: String
    var emptyLabel: String = "No extra limit"

    private let choices = [15, 30, 45, 60, 90, 120, 180]

    var body: some View {
        Menu {
            Button(emptyLabel) { minutes = nil }
            ForEach(choices, id: \.self) { value in
                Button(Fmt.long(value * 60)) { minutes = value }
            }
        } label: {
            Text("\(title): \(minutes.map { Fmt.long($0 * 60) } ?? emptyLabel)")
                .font(.system(size: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
