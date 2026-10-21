import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// Settings window with toolbar tabs, like most Mac apps.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let size = NSSize(width: 680, height: 560)
    private let tabs = SettingsTabs()

    init(store: Store, updates: UpdateCheck, showWelcome: @escaping () -> Void) {
        tabs.tabStyle = .toolbar
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)

        add("General", "gearshape", GeneralPane(store: store, updates: updates, showWelcome: showWelcome))
        add("Tracking", "square.grid.2x2", TrackingPane(store: store))
        add("Focus", "moon", FocusPane(store: store))
        add("Log", "text.bubble", LogPane(store: store))
        window.setContentSize(Self.size)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func add<V: View>(_ title: String, _ symbol: String, _ view: V) {
        let host = NSHostingController(rootView: view.frame(width: Self.size.width, height: Self.size.height))
        host.title = title
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }

    func select(tab index: Int) {
        guard tabs.tabViewItems.indices.contains(index) else { return }
        tabs.selectedTabViewItemIndex = index
    }
}

/// Keeps the first field of a tab from grabbing keyboard focus when the tab opens.
final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        DispatchQueue.main.async { [weak self] in self?.view.window?.makeFirstResponder(nil) }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        DispatchQueue.main.async { [weak self] in self?.view.window?.makeFirstResponder(nil) }
    }
}

// MARK: - General

struct GeneralPane: View {
    @ObservedObject var store: Store
    @ObservedObject var updates: UpdateCheck
    var showWelcome: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        let limit = Binding<Double>(
            get: { Double(store.settings.dailyLimitMinutes) },
            set: { store.settings.dailyLimitMinutes = Self.round15($0) })

        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Daily limit")
                        Spacer()
                        Text(Fmt.long(store.settings.dailyLimitMinutes * 60))
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                    }
                    Slider(value: limit, in: 15...480) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("15 min").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    } maximumValueLabel: {
                        Text("8 h").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    }
                    Text("All tracked sites and apps together. Each one can also have its own limit in Tracking.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Picker("Stop counting after", selection: $store.settings.idleThresholdSeconds) {
                    ForEach(idleChoices, id: \.self) { s in
                        Text(idleLabel(s)).tag(s)
                    }
                }
            } header: {
                Text("Limit")
            }

            Section {
                Toggle("Notify me at 80% and at the limit", isOn: $store.settings.notificationsEnabled)
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Show a screen at the limit", isOn: $store.settings.softBlockEnabled)
                    Text("You can snooze it for 5 or 15 minutes, or turn it off for the day.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            } header: {
                Text("At the limit")
            }

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
                    Text(loginError).font(.system(size: 11)).foregroundStyle(Theme.over)
                }
                HStack {
                    Text("Welcome window")
                    Spacer()
                    Button("Show Again", action: showWelcome)
                }
            } header: {
                Text("Startup")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lapse \(version)")
                        Text(updates.available.map { "Lapse \($0) is out." } ?? "Lapse checks GitHub for a new version once a day.")
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if updates.available != nil {
                        Button("Download", action: updates.openDownload)
                    } else {
                        Button("Check Now") { updates.checkNow {} }
                    }
                }
                Text("Sites are read from Safari, Chrome, Arc, Brave, Edge and Vivaldi. Your Mac asks once per browser.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
    }

    static func round15(_ value: Double) -> Int { max(15, Int((value / 15).rounded()) * 15) }

    private var idleChoices: [Int] {
        var list = [30, 60, 120, 300, 600]
        let current = store.settings.idleThresholdSeconds
        if !list.contains(current) { list.append(current); list.sort() }
        return list
    }

    private func idleLabel(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) seconds idle" }
        if seconds % 60 == 0 {
            let m = seconds / 60
            return m == 1 ? "1 minute idle" : "\(m) minutes idle"
        }
        return "\(seconds) seconds idle"
    }
}

// MARK: - Tracking

struct TrackingPane: View {
    @ObservedObject var store: Store
    @State private var selection: String? = "x.com"
    @State private var addingSite = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Rectangle().fill(Theme.hairline).frame(width: 0.5)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            for app in store.settings.apps { _ = store.icon(forBundleID: app.id) }
            if selection == nil || store.iconSource(for: selection!) == nil {
                selection = store.settings.sites.first?.id
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("Sites") {
                    ForEach(store.settings.sites) { site in
                        sidebarRow(name: site.name, icon: .site(site, favicon: store.favicons[site.id]),
                                   enabled: site.enabled, limit: site.dailyLimitMinutes)
                            .tag(site.id)
                            .contextMenu { Button("Remove \(site.name)") { remove(site.id) } }
                    }
                }
                Section("Apps") {
                    ForEach(store.settings.apps) { app in
                        sidebarRow(name: app.name, icon: .app(app, icon: store.appIcons[app.id]),
                                   enabled: app.enabled, limit: app.dailyLimitMinutes)
                            .tag(app.id)
                            .contextMenu { Button("Remove \(app.name)") { remove(app.id) } }
                    }
                }
            }
            .listStyle(.sidebar)

            HStack(spacing: 0) {
                Menu {
                    Button("Add a Site…") { addingSite = true }
                    Button("Add an App…") { addApp() }
                } label: {
                    Image(systemName: "plus").frame(width: 22, height: 18)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add a site or app")
                .popover(isPresented: $addingSite, arrowEdge: .top) { addSitePopover }

                Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 14).padding(.horizontal, 2)

                Button {
                    if let selection { remove(selection) }
                } label: {
                    Image(systemName: "minus").frame(width: 22, height: 18)
                }
                .buttonStyle(.borderless)
                .disabled(selection == nil)
                .help("Remove")
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        }
    }

    private func sidebarRow(name: String, icon: ItemIcon.Source, enabled: Bool, limit: Int?) -> some View {
        HStack(spacing: 8) {
            ItemIcon(source: icon, size: 18)
                .opacity(enabled ? 1 : 0.45)
            Text(name)
                .foregroundStyle(enabled ? Theme.ink : Theme.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !enabled {
                Text("Off").font(.system(size: 11)).foregroundStyle(Theme.faint)
            } else if let limit {
                Text(Fmt.long(limit * 60)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.faint)
            }
        }
    }

    private var addSitePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a site").font(.system(size: 13, weight: .semibold))
            TextField("news.ycombinator.com", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit(commitSite)
            HStack {
                Spacer()
                Button("Cancel") { addingSite = false; draft = "" }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: commitSite)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let i = store.settings.sites.firstIndex(where: { $0.id == id }) {
            SiteDetail(store: store, index: i)
                .id(id)
        } else if let id = selection, let i = store.settings.apps.firstIndex(where: { $0.id == id }) {
            AppDetail(store: store, index: i)
                .id(id)
        } else {
            Text("Pick a site or app.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Actions

    private func commitSite() {
        let raw = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let before = Set(store.settings.sites.map(\.id))
        store.addSite(domain: raw)
        if let added = store.settings.sites.first(where: { !before.contains($0.id) }) {
            selection = added.id
        }
        draft = ""
        addingSite = false
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        panel.message = "Choose a Mac app to track."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let before = Set(store.settings.apps.map(\.id))
        store.addApp(at: url)
        if let added = store.settings.apps.first(where: { !before.contains($0.id) }) {
            selection = added.id
        }
    }

    private func remove(_ id: String) {
        let ids = store.settings.sites.map(\.id) + store.settings.apps.map(\.id)
        let next = ids.firstIndex(of: id).flatMap { i in ids.indices.contains(i + 1) ? ids[i + 1] : (i > 0 ? ids[i - 1] : nil) }
        selection = next
        DispatchQueue.main.async {
            if store.settings.sites.contains(where: { $0.id == id }) { store.removeSite(id) } else { store.removeApp(id) }
        }
    }
}

/// Minute choices shared by the limit pickers.
private let limitChoices = [15, 30, 45, 60, 90, 120, 180, 240]

private struct LimitPickers: View {
    @ObservedObject var store: Store
    @Binding var daily: Int?
    @Binding var focus: Int?

    var body: some View {
        Picker("Daily limit", selection: $daily) {
            Text("Only the overall limit").tag(Int?.none)
            Divider()
            ForEach(limitChoices, id: \.self) { m in Text(Fmt.long(m * 60)).tag(Int?.some(m)) }
        }
        if store.settings.focus.mode == .stricter {
            Picker("During focus hours", selection: $focus) {
                Text(daily == nil ? "Only the focus limit" : "Same as the daily limit").tag(Int?.none)
                Divider()
                ForEach(limitChoices, id: \.self) { m in Text(Fmt.long(m * 60)).tag(Int?.some(m)) }
            }
        }
    }
}

private struct FrictionSection: View {
    let name: String
    @Binding var friction: FrictionSettings

    var body: some View {
        Section {
            Picker("Pause screen", selection: $friction.kind) {
                ForEach(FrictionKind.allCases) { k in Text(k.label).tag(k) }
            }
            if friction.kind == .countdown {
                Picker("Length", selection: $friction.seconds) {
                    ForEach(FrictionSettings.lengths, id: \.self) { s in Text("\(s) seconds").tag(s) }
                }
            }
            if friction.kind != .off {
                Picker("Show it", selection: $friction.trigger) {
                    ForEach(FrictionTrigger.allCases) { t in Text(t.label).tag(t) }
                }
            }
        } header: {
            Text("Before it opens")
        } footer: {
            Text(footer)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: String {
        switch friction.kind {
        case .off: return "Lapse can make you wait a few seconds, or type why, before \(name) opens."
        case .countdown: return "\(name) opens after the countdown. You can back out instead. It all goes in the Log."
        case .reason: return "You type why you're opening \(name) first. Reasons go in the Log."
        }
    }
}

private struct DetailHeader: View {
    let icon: ItemIcon.Source
    let name: String
    let detail: String
    @Binding var enabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(source: icon, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Toggle("Track \(name)", isOn: $enabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

private struct SiteDetail: View {
    @ObservedObject var store: Store
    let index: Int

    private var site: Binding<SiteConfig> {
        Binding(get: { store.settings.sites.indices.contains(index) ? store.settings.sites[index] : SiteConfig.defaults[0] },
                set: { if store.settings.sites.indices.contains(index) { store.settings.sites[index] = $0 } })
    }

    var body: some View {
        let s = site.wrappedValue
        Form {
            Section {
                DetailHeader(icon: .site(s, favicon: store.favicons[s.id]), name: s.name,
                             detail: s.domains.joined(separator: ", "), enabled: site.enabled)
            }
            if s.enabled {
                Section {
                    LimitPickers(store: store, daily: site.dailyLimitMinutes, focus: site.focusLimitMinutes)
                } header: {
                    Text("Limits")
                }
                if let rule = FeedRules.rule(for: s.id) {
                    Section {
                        Toggle("Only count the feed", isOn: site.feedOnly)
                    } header: {
                        Text("Counting")
                    } footer: {
                        Text(rule.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                FrictionSection(name: s.name, friction: site.friction)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppDetail: View {
    @ObservedObject var store: Store
    let index: Int

    private var app: Binding<AppConfig> {
        Binding(get: { store.settings.apps.indices.contains(index) ? store.settings.apps[index] : AppConfig.defaults[0] },
                set: { if store.settings.apps.indices.contains(index) { store.settings.apps[index] = $0 } })
    }

    var body: some View {
        let a = app.wrappedValue
        Form {
            Section {
                DetailHeader(icon: .app(a, icon: store.appIcons[a.id]), name: a.name, detail: a.id, enabled: app.enabled)
            } footer: {
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.id) == nil {
                    Text("\(a.name) isn't installed on this Mac.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if a.enabled {
                Section {
                    LimitPickers(store: store, daily: app.dailyLimitMinutes, focus: app.focusLimitMinutes)
                } header: {
                    Text("Limits")
                } footer: {
                    Text("Time counts while \(a.name) is the app in front.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                FrictionSection(name: a.name, friction: app.friction)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Focus

struct FocusPane: View {
    @ObservedObject var store: Store

    private static let dayLetters = ["S", "M", "T", "W", "T", "F", "S"]
    private static let dayNames = Calendar.current.weekdaySymbols

    var body: some View {
        Form {
            if let source = store.focusSource {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "moon.fill").foregroundStyle(Theme.ink)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(statusTitle(source)).font(.system(size: 13, weight: .medium))
                            Text(store.focusMode == .block ? "Tracked sites and apps are blocked." : "Stricter limits are on.")
                                .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Button("End Now") { store.stopFocus() }
                    }
                }
            }

            Section {
                Toggle("Turn on focus hours on a schedule", isOn: $store.settings.focus.enabled)
                if store.settings.focus.enabled {
                    HStack {
                        Text("Days")
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { i in dayButton(i) }
                        }
                    }
                    HStack {
                        Text("Hours")
                        Spacer()
                        DatePicker("From", selection: focusStart, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("to").foregroundStyle(Theme.muted)
                        DatePicker("To", selection: focusEnd, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
            } header: {
                Text("Schedule")
            }

            Section {
                Picker("Tracked sites and apps", selection: $store.settings.focus.mode) {
                    Text("Get a stricter limit").tag(FocusMode.stricter)
                    Text("Are blocked").tag(FocusMode.block)
                }
                if store.settings.focus.mode == .stricter {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Focus limit")
                            Spacer()
                            Text(Fmt.long(store.settings.focus.dailyLimitMinutes * 60))
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                        }
                        Slider(value: focusLimit, in: 15...240)
                    }
                }
            } header: {
                Text("During focus hours")
            } footer: {
                Text(store.settings.focus.mode == .block
                     ? "The limit screen comes up as soon as a tracked site or app is in front, unless that screen is off in General."
                     : "This replaces the daily limit while focus hours are on. The menu bar ring follows it.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                if Signing.hasTeam {
                    autoRow(symbol: "moon.circle", title: "With a Focus",
                            detail: "Add Lapse as a filter to any Focus, like Work. Focus hours turn on with that Focus and off when it ends. In System Settings, open Focus, pick one, then Add Filter.",
                            button: "Open Focus", action: openFocusSettings)
                    autoRow(symbol: "square.on.square", title: "With Shortcuts",
                            detail: "Lapse has actions to start or end focus hours, pause tracking, get today's time and change a limit. Search for Lapse in the Shortcuts app.",
                            button: "Open Shortcuts", action: openShortcuts)
                } else {
                    autoRow(symbol: "moon.circle", title: "With a Focus",
                            detail: "On macOS 26 and later, make two Focus automations in Shortcuts. One opens lapse://focus/start when the Focus turns on. The other opens lapse://focus/stop when it turns off.",
                            button: "Open Shortcuts", action: openShortcuts)
                    autoRow(symbol: "square.on.square", title: "With Shortcuts",
                            detail: "Put one of these in an Open URLs action. For today's minutes, use the last line in a Run Shell Script action.",
                            button: nil, action: {})
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Self.links, id: \.self) { line in
                            Text(line)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .padding(.leading, 34)
                }
            } header: {
                Text("Turn on automatically")
            } footer: {
                Text(Signing.hasTeam
                     ? "lapse:// links work too. The README lists them."
                     : "Shortcuts actions and Focus filters only work in a copy of Lapse signed by a developer team. This one is signed ad hoc, so the links do those jobs instead.")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
    }

    private static let links = [
        "lapse://focus/start?minutes=60",
        "lapse://focus/stop",
        "lapse://pause?minutes=30",
        "lapse://resume",
        "lapse://limit?minutes=20&site=reddit.com",
        "defaults read com.acerothman.lapse todayMinutes",
    ]

    private func autoRow(symbol: String, title: String, detail: String, button: String?,
                         action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(Theme.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let button { Button(button, action: action) }
        }
    }

    private func openFocusSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openShortcuts() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func statusTitle(_ source: Store.FocusSource) -> String {
        switch source {
        case .filter: return "On, from your Focus"
        case .manual, .schedule:
            if let end = store.focusEnds() { return "On until \(Fmt.time(end))" }
            return "On until you end it"
        }
    }

    private func dayButton(_ index: Int) -> some View {
        let on = store.settings.focus.days.indices.contains(index) && store.settings.focus.days[index]
        return Button(Self.dayLetters[index]) {
            guard store.settings.focus.days.indices.contains(index) else { return }
            var days = store.settings.focus.days
            days[index].toggle()
            store.settings.focus.days = days
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 24, height: 24)
        .foregroundStyle(on ? Color(nsColor: .windowBackgroundColor) : Theme.muted)
        .background(Circle().fill(on ? Theme.ink : Theme.tile))
        .help(Self.dayNames.indices.contains(index) ? Self.dayNames[index] : "")
        .accessibilityLabel(Self.dayNames.indices.contains(index) ? Self.dayNames[index] : "")
        .accessibilityValue(on ? "On" : "Off")
    }

    private var focusLimit: Binding<Double> {
        Binding(get: { Double(store.settings.focus.dailyLimitMinutes) },
                set: { store.settings.focus.dailyLimitMinutes = GeneralPane.round15($0) })
    }

    private var focusStart: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: store.settings.focus.startMinutes) },
                set: { store.settings.focus.startMinutes = Self.minutes(from: $0) })
    }

    private var focusEnd: Binding<Date> {
        Binding(get: { Self.date(fromMinutes: store.settings.focus.endMinutes) },
                set: { store.settings.focus.endMinutes = Self.minutes(from: $0) })
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
}

// MARK: - Log

struct LogPane: View {
    @ObservedObject var store: Store
    @State private var confirmClear = false

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f
    }()

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private struct Day: Identifiable {
        let id: String
        let title: String
        let entries: [FrictionEntry]
    }

    private var days: [Day] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: store.log.reversed()) { DayKey.key($0.date) }
        return groups.keys.sorted(by: >).map { key in
            let entries = groups[key] ?? []
            let date = entries.first?.date ?? Date()
            let title = cal.isDateInToday(date) ? "Today" : (cal.isDateInYesterday(date) ? "Yesterday" : Self.dayFmt.string(from: date))
            return Day(id: key, title: title, entries: entries)
        }
    }

    var body: some View {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let week = store.log.filter { $0.date >= weekAgo }
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 28) {
                stat("\(week.count)", "pause screens this week")
                stat("\(week.filter { !$0.opened }.count)", "times you backed out")
                stat("\(week.filter { !($0.reason ?? "").isEmpty }.count)", "reasons typed")
                Spacer()
                Button("Clear Log…") { confirmClear = true }
                    .disabled(store.log.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            Rectangle().fill(Theme.hairline).frame(height: 0.5)

            if store.log.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.faint)
                    Text("Nothing here yet")
                        .font(.system(size: 13, weight: .medium))
                    Text("Turn on a pause screen for a site or app in Tracking. Each one, and any reason you type, shows up here.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(days) { day in
                        Section(day.title) {
                            ForEach(day.entries) { entry in row(entry) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog("Clear the log?", isPresented: $confirmClear) {
            Button("Clear Log", role: .destructive) { store.clearLog() }
        } message: {
            Text("This removes every entry and reason. It can't be undone.")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Theme.number(20))
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
    }

    private func row(_ entry: FrictionEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.timeFmt.string(from: entry.date))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.faint)
                .frame(width: 62, alignment: .leading)
            Group {
                if let icon = store.iconSource(for: entry.itemID) {
                    ItemIcon(source: icon, size: 16)
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }
            }
            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.system(size: 12, weight: .medium))
                if let reason = entry.reason, !reason.isEmpty {
                    Text(reason).font(.system(size: 12)).textSelection(.enabled)
                } else if entry.kind == .countdown {
                    Text("Countdown, no reason asked").font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else {
                    Text("No reason").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            Tag(text: entry.opened ? "Opened" : "Backed out")
        }
        .padding(.vertical, 3)
    }
}
