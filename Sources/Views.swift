import SwiftUI
import Charts
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

struct SiteIcon: View {
    let site: SiteConfig
    var favicon: NSImage? = nil   // fetched logo for user-added sites
    var size: CGFloat = 24

    private var bundled: NSImage? {
        guard let name = site.icon,
              let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        let corner = size * 0.25
        let glyph = bundled
        ZStack {
            if let glyph {
                // Built-in site: white logo on its brand color.
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color(hex: site.colorHex))
                Image(nsImage: glyph)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.54, height: size * 0.54)
            } else if let favicon {
                // User-added site: full-color favicon on a white tile, like an app icon.
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white)
                Image(nsImage: favicon)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.7, height: size * 0.7)
            } else {
                // Loading or failed: neutral letter tile.
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color(hex: "#8E8E93"))
                Text(site.name.prefix(1).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .animation(.easeOut(duration: 0.2), value: favicon != nil)
    }
}

struct UsageBar: View {
    let fraction: Double
    var height: CGFloat = 3
    var color: Color = .blue

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(0, min(1, fraction)) * g.size.width)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}

struct PopoverView: View {
    @ObservedObject var store: Store
    let openSettings: () -> Void
    let checkForUpdates: () -> Void
    let quit: () -> Void

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        return f
    }()

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        let total = store.todayTotal
        let limit = store.limitSeconds
        let over = total >= limit
        let today = store.today
        let sites = store.enabledSites.sorted { (today.seconds[$0.id] ?? 0) > (today.seconds[$1.id] ?? 0) }
        let apps = store.enabledApps.sorted { (today.seconds[$0.id] ?? 0) > (today.seconds[$1.id] ?? 0) }
        let top = max(
            sites.map { today.seconds[$0.id] ?? 0 }.max() ?? 0,
            apps.map { today.seconds[$0.id] ?? 0 }.max() ?? 0,
            1
        )
        let week = store.lastSevenDays()
        let avg = week.map(\.seconds).reduce(0, +) / max(week.count, 1)
        let chartLimit = limit > 0 ? limit : max(store.settings.dailyLimitMinutes, 1) * 60
        let summary: String = {
            if limit == 0 { return "Focus hours. No time on tracked sites and apps." }
            if over { return "of \(Fmt.long(limit)) · \(Fmt.long(max(0, total - limit))) over" }
            return "of \(Fmt.long(limit)) · \(Fmt.long(max(0, limit - total))) left"
        }()

        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lapse").font(.system(size: 13, weight: .semibold))
                    Text("Today, \(Self.dateFmt.string(from: Date()))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape").font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Settings")
            }

            // Summary
            Text(Fmt.long(total))
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .animation(.default, value: total)
                .padding(.top, 12)
            Text(summary)
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .padding(.top, 1)
            UsageBar(fraction: limit == 0 ? 1 : Double(total) / Double(max(limit, 1)), height: 5, color: over ? .red : .blue)
                .padding(.top, 9)

            Divider().padding(.vertical, 10)

            // Sites
            Text("Sites").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 4)
            if sites.isEmpty && apps.isEmpty {
                Text("No sites or apps turned on. Add one in Settings.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            ForEach(sites) { site in
                usageRow(name: site.name,
                         subtitle: site.id,
                         id: site.id,
                         icon: AnyView(SiteIcon(site: site, favicon: store.favicons[site.id])),
                         today: today,
                         top: top)
            }
            if !apps.isEmpty {
                Text("Apps").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                ForEach(apps) { app in
                    usageRow(name: app.name,
                             subtitle: "App",
                             id: app.id,
                             icon: AnyView(AppIconView(image: store.appIcons[app.id], name: app.name)),
                             today: today,
                             top: top)
                }
            }

            Divider().padding(.vertical, 10)

            // Week
            HStack {
                Text("This week").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("Avg \(Fmt.long(avg)) a day").font(.system(size: 11))
            }
            .foregroundStyle(.secondary)

            WeekChart(week: week, limitSeconds: chartLimit)
                .frame(height: 90)
                .padding(.top, 8)

            Divider().padding(.vertical, 10)

            // Footer
            HStack {
                Text("Version \(version)").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Check for updates", action: checkForUpdates)
                Button("Settings…", action: openSettings)
                Button("Quit", action: quit)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 316)
    }

    private func usageRow(name: String, subtitle: String, id: String, icon: AnyView, today: DayRecord, top: Int) -> some View {
        let secs = today.seconds[id] ?? 0
        let visits = today.visits[id] ?? 0
        let itemOver = store.itemLimitSeconds(for: id).map { secs >= $0 } ?? false
        let overallOver = store.limitSeconds == 0 || store.todayTotal >= store.limitSeconds
        let over = itemOver || overallOver
        return HStack(spacing: 9) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(name).font(.system(size: 13, weight: .medium))
                    if store.currentSiteID == id {
                        Circle().fill(Color.blue).frame(width: 5, height: 5)
                            .help("Active now")
                    }
                    Spacer()
                    Text(Fmt.long(secs)).font(.system(size: 13)).monospacedDigit()
                        .foregroundStyle(over ? Color.red : Color.primary)
                }
                Text("\(subtitle) · \(visits) \(visits == 1 ? "visit" : "visits")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                UsageBar(fraction: Double(secs) / Double(top), color: over ? .red : .blue)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 5)
    }
}

struct AppIconView: View {
    let image: NSImage?
    let name: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(hex: "#8E8E93"))
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
            ForEach(week) { d in
                BarMark(x: .value("Day", d.label),
                        y: .value("Minutes", Double(d.seconds) / 60))
                    .foregroundStyle(color(for: d))
                    .cornerRadius(3)
            }
            RuleMark(y: .value("Limit", limitMin))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .annotation(position: .top, alignment: .trailing, spacing: 1) {
                    Text(Fmt.long(limitSeconds)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
        }
        .chartYScale(domain: 0...max(limitMin * 1.12, maxMin * 1.05, 1))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .animation(.easeOut(duration: 0.35), value: week.map(\.seconds))
    }

    private func color(for d: Store.WeekDay) -> Color {
        if d.seconds > limitSeconds { return .red }
        return d.isToday ? .blue : .blue.opacity(0.45)
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    var showWelcome: () -> Void = {}
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var newDomain = ""
    @State private var loginError: String?

    var body: some View {
        let limitBinding = Binding<Double>(
            get: { Double(store.settings.dailyLimitMinutes) },
            set: { store.settings.dailyLimitMinutes = Int($0) })

        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Daily limit")
                        Spacer()
                        Text(Fmt.long(store.settings.dailyLimitMinutes * 60))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: limitBinding, in: 15...480, step: 15)
                }
                Stepper(value: $store.settings.idleThresholdSeconds, in: 15...600, step: 15) {
                    HStack {
                        Text("Pause after no activity for")
                        Spacer()
                        Text("\(store.settings.idleThresholdSeconds) s").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Toggle("Notify me at 80% and at the limit", isOn: $store.settings.notificationsEnabled)
                Toggle("Show a screen at the limit", isOn: $store.settings.softBlockEnabled)
                Text("Snooze it for a few minutes, or turn it off for the day.")
                    .font(.caption).foregroundStyle(.secondary)
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
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Sites") {
                ForEach($store.settings.sites) { $site in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $site.enabled) {
                            HStack(spacing: 8) {
                                SiteIcon(site: site, favicon: store.favicons[site.id], size: 20)
                                Text(site.name)
                                Text(site.id).foregroundStyle(.secondary)
                            }
                        }
                        if site.enabled {
                            limitMenus(daily: $site.dailyLimitMinutes, focus: $site.focusLimitMinutes)
                        }
                    }
                    .contextMenu {
                        Button("Remove \(site.name)", role: .destructive) {
                            let id = site.id
                            DispatchQueue.main.async { store.removeSite(id) }
                        }
                    }
                }
                HStack {
                    TextField("Add a site, like news.ycombinator.com", text: $newDomain)
                        .onSubmit(add)
                    Button("Add", action: add).disabled(newDomain.isEmpty)
                }
            }

            Section("Apps") {
                ForEach($store.settings.apps) { $app in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $app.enabled) {
                            HStack(spacing: 8) {
                                AppIconView(image: store.appIcons[app.id], name: app.name, size: 20)
                                Text(app.name)
                                Text(app.id).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        if app.enabled {
                            limitMenus(daily: $app.dailyLimitMinutes, focus: $app.focusLimitMinutes)
                        }
                    }
                    .contextMenu {
                        Button("Remove \(app.name)", role: .destructive) {
                            let id = app.id
                            DispatchQueue.main.async { store.removeApp(id) }
                        }
                    }
                }
                Button("Add an app…") { addApp() }
                Text("Time counts while that app is in front. The icon comes from the app itself.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Focus hours") {
                Toggle("Use focus hours", isOn: $store.settings.focus.enabled)
                if store.settings.focus.enabled {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { index in
                            let on = store.settings.focus.days.indices.contains(index) && store.settings.focus.days[index]
                            Button(Self.dayLetters[index]) {
                                toggleDay(index)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: on ? .semibold : .regular))
                            .frame(width: 28, height: 28)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(Circle().fill(on ? Color.accentColor : Color.primary.opacity(0.08)))
                        }
                    }
                    HStack {
                        Text("From")
                        DatePicker("", selection: focusStart, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                        Text("to")
                        DatePicker("", selection: focusEnd, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    Picker("During these hours", selection: $store.settings.focus.mode) {
                        Text("Stricter limits").tag(FocusMode.stricter)
                        Text("Block outright").tag(FocusMode.block)
                    }
                    if store.settings.focus.mode == .stricter {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Focus limit")
                                Spacer()
                                Text(Fmt.long(store.settings.focus.dailyLimitMinutes * 60))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            Slider(value: focusLimit, in: 15...240, step: 15)
                        }
                    }
                    Text(store.settings.focus.mode == .block
                         ? "Tracked sites and apps bring up the screen right away."
                         : "The menu bar ring uses this limit during the window.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Welcome to Lapse", action: showWelcome)
            }

            Section {
                Text("Works with Safari, Chrome, Arc, Brave, Edge and Vivaldi. Your Mac asks once per browser before Lapse can see which site you're on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 680)
        .onAppear {
            for app in store.settings.apps {
                _ = store.icon(forBundleID: app.id)
            }
        }
    }

    private static let dayLetters = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

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

    private func limitMenus(daily: Binding<Int?>, focus: Binding<Int?>) -> some View {
        HStack(spacing: 12) {
            MinuteLimitMenu(minutes: daily, title: "Limit")
            if store.settings.focus.enabled && store.settings.focus.mode == .stricter {
                MinuteLimitMenu(minutes: focus, title: "Focus")
            }
        }
        .padding(.leading, 22)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a Mac app to track."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addApp(at: url)
    }

    private func toggleDay(_ index: Int) {
        guard store.settings.focus.days.indices.contains(index) else { return }
        var days = store.settings.focus.days
        days[index].toggle()
        store.settings.focus.days = days
    }

    private func add() {
        store.addSite(domain: newDomain)
        newDomain = ""
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
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
