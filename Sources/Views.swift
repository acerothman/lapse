import SwiftUI
import Charts
import AppKit
import ServiceManagement

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
        let topSeconds = max(sites.map { today.seconds[$0.id] ?? 0 }.max() ?? 0, 1)
        let week = store.lastSevenDays()
        let avg = week.map(\.seconds).reduce(0, +) / max(week.count, 1)

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
            Text(over
                 ? "of \(Fmt.long(limit)) · \(Fmt.long(total - limit)) over"
                 : "of \(Fmt.long(limit)) · \(Fmt.long(limit - total)) left")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .padding(.top, 1)
            UsageBar(fraction: Double(total) / Double(max(limit, 1)), height: 5, color: over ? .red : .blue)
                .padding(.top, 9)

            Divider().padding(.vertical, 10)

            // Sites
            Text("Sites").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.bottom, 4)
            if sites.isEmpty {
                Text("No sites turned on. Add one in Settings.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 6)
            }
            ForEach(sites) { site in
                let secs = today.seconds[site.id] ?? 0
                let visits = today.visits[site.id] ?? 0
                HStack(spacing: 9) {
                    SiteIcon(site: site, favicon: store.favicons[site.id])
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(site.name).font(.system(size: 13, weight: .medium))
                            if store.currentSiteID == site.id {
                                Circle().fill(Color.blue).frame(width: 5, height: 5)
                                    .help("Active now")
                            }
                            Spacer()
                            Text(Fmt.long(secs)).font(.system(size: 13)).monospacedDigit()
                        }
                        Text("\(site.id) · \(visits) \(visits == 1 ? "visit" : "visits")")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        UsageBar(fraction: Double(secs) / Double(topSeconds))
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 5)
            }

            Divider().padding(.vertical, 10)

            // Week
            HStack {
                Text("This week").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("Avg \(Fmt.long(avg)) a day").font(.system(size: 11))
            }
            .foregroundStyle(.secondary)

            WeekChart(week: week, limitSeconds: limit)
                .frame(height: 90)
                .padding(.top, 8)

            Divider().padding(.vertical, 10)

            // Footer
            HStack {
                Text("Version \(version)").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
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
                    Toggle(isOn: $site.enabled) {
                        HStack(spacing: 8) {
                            SiteIcon(site: site, favicon: store.favicons[site.id], size: 20)
                            Text(site.name)
                            Text(site.id).foregroundStyle(.secondary)
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

            Section {
                Button("Welcome to Lapse", action: showWelcome)
            }

            Section {
                Text("Works with Safari, Chrome, Arc, Brave, Edge and Vivaldi. Your Mac asks once per browser before Lapse can see which site you're on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 620)
    }

    private func add() {
        store.addSite(domain: newDomain)
        newDomain = ""
    }
}
