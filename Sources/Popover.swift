import SwiftUI
import Charts
import AppKit

struct PopoverView: View {
    @ObservedObject var store: Store
    @ObservedObject var updates: UpdateCheck
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

    struct Item: Identifiable {
        let id: String
        let name: String
        let detail: String
        let icon: ItemIcon.Source
        let seconds: Int
        let visits: Int
        let feedOnly: Bool
    }

    private var items: [Item] {
        let today = store.today
        let sites = store.enabledSites.map { s in
            Item(id: s.id, name: s.name, detail: s.id, icon: .site(s, favicon: store.favicons[s.id]),
                 seconds: today.seconds[s.id] ?? 0, visits: today.visits[s.id] ?? 0, feedOnly: s.countsFeedOnly)
        }
        let apps = store.enabledApps.map { a in
            Item(id: a.id, name: a.name, detail: "App", icon: .app(a, icon: store.appIcons[a.id]),
                 seconds: today.seconds[a.id] ?? 0, visits: today.visits[a.id] ?? 0, feedOnly: false)
        }
        return (sites + apps).sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            hero
            notices
            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.horizontal, Theme.gutter)
            list
            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.horizontal, Theme.gutter)
            week
            footer
        }
        .frame(width: 320)
    }

    // MARK: Header and hero

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .font(.system(size: 13, weight: .semibold))
            Text(Self.dateFmt.string(from: Date()))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 14)
    }

    private var hero: some View {
        let total = store.todayTotal
        let limit = store.limitSeconds
        let over = limit == 0 || total >= limit
        let focus = store.isFocusHours()
        let summary: String = {
            if limit == 0 { return "Tracked sites and apps are blocked during focus hours." }
            let kind = focus ? "focus limit" : "limit"
            if over { return "\(Fmt.long(total - limit)) over your \(Fmt.long(limit)) \(kind)" }
            return "\(Fmt.long(limit - total)) left of your \(Fmt.long(limit)) \(kind)"
        }()
        return VStack(alignment: .leading, spacing: 0) {
            Text(Fmt.long(total))
                .font(Theme.number(30))
                .tracking(-0.4)
                .contentTransition(.numericText())
                .animation(.default, value: total)
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(over && limit > 0 ? Theme.over : Theme.muted)
                .padding(.top, 2)
            ProgressTrack(fraction: limit == 0 ? 1 : Double(total) / Double(max(limit, 1)), over: over, height: 4)
                .padding(.top, 12)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: Notices

    @ViewBuilder
    private var notices: some View {
        let update = updates.available
        let paused = store.pausedUntil
        let focus = store.focusSource
        if update != nil || paused != nil || focus != nil {
            VStack(spacing: 0) {
                if let update {
                    notice(symbol: "arrow.down.circle", title: "Lapse \(update) is out", detail: nil,
                           action: "Download", perform: updates.openDownload)
                }
                if let paused {
                    if update != nil { divider }
                    notice(symbol: "pause.circle",
                           title: paused == .distantFuture ? "Paused until you resume" : "Paused until \(Fmt.time(paused))",
                           detail: "Nothing counts and nothing gets blocked.",
                           action: "Resume", perform: store.resume)
                }
                if let focus {
                    if update != nil || paused != nil { divider }
                    notice(symbol: "moon", title: focusTitle(focus), detail: focusDetail,
                           action: "End", perform: store.stopFocus)
                }
            }
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.tile))
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 38)
    }

    private func focusTitle(_ source: Store.FocusSource) -> String {
        switch source {
        case .filter: return "Focus hours, from your Focus"
        case .manual, .schedule:
            if let end = store.focusEnds() { return "Focus hours until \(Fmt.time(end))" }
            return "Focus hours until you end them"
        }
    }

    private var focusDetail: String {
        store.focusMode == .block ? "Tracked sites and apps are blocked." : "Stricter limits are on."
    }

    private func notice(symbol: String, title: String, detail: String?, action: String,
                        perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            Button(action, action: perform)
                .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: List

    private var list: some View {
        let items = self.items
        let top = max(items.map(\.seconds).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Sites and apps")
                .padding(.bottom, 6)
            if items.isEmpty {
                Text("Nothing is turned on. Pick sites and apps in Settings.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.vertical, 8)
            }
            ForEach(items) { item in
                row(item, top: top)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, 12)
    }

    private func row(_ item: Item, top: Int) -> some View {
        let over = store.isOver(item.id) && item.seconds > 0
        let active = store.currentSiteID == item.id
        let subtitle: String = {
            if active { return "Now · \(Fmt.session(store.sessionSeconds))" }
            let visits = "\(item.visits) \(item.visits == 1 ? "visit" : "visits")"
            return item.feedOnly ? "Feed only · \(visits)" : "\(item.detail) · \(visits)"
        }()
        return HStack(alignment: .center, spacing: 10) {
            ItemIcon(source: item.icon, size: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.long(item.seconds))
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(over ? Theme.over : (item.seconds == 0 ? Theme.faint : Theme.ink))
                }
                HStack(spacing: 4) {
                    if active {
                        Circle().fill(Theme.ink).frame(width: 5, height: 5)
                    }
                    Text(subtitle)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(active ? Theme.ink : Theme.muted)
                        .lineLimit(1)
                }
                ProgressTrack(fraction: Double(item.seconds) / Double(top), over: over, height: 2.5)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 6)
        .help(item.feedOnly ? "\(item.name) counts only its feed. Change that in Settings." : item.name)
    }

    // MARK: Week

    private var week: some View {
        let days = store.lastSevenDays()
        let avg = days.map(\.seconds).reduce(0, +) / max(days.count, 1)
        let limit = store.settings.dailyLimitMinutes * 60
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Last 7 days", trailing: "Avg \(Fmt.long(avg))")
            WeekChart(week: days, limitSeconds: limit)
                .frame(height: 78)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            if store.isPaused {
                Button { store.resume() } label: {
                    Label("Resume", systemImage: "play")
                }
                .buttonStyle(QuietButtonStyle())
            } else {
                Menu {
                    Button("15 minutes") { store.pause(minutes: 15) }
                    Button("30 minutes") { store.pause(minutes: 30) }
                    Button("1 hour") { store.pause(minutes: 60) }
                    Button("Until tomorrow") { store.pauseUntilTomorrow() }
                    Button("Until I resume") { store.pause(minutes: nil) }
                } label: {
                    Label("Pause", systemImage: "pause")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .modifier(QuietMenu())
            }

            if store.isFocusHours() {
                Button { store.stopFocus() } label: {
                    Label("End focus", systemImage: "moon.fill")
                }
                .buttonStyle(QuietButtonStyle())
            } else {
                Menu {
                    Button("30 minutes") { store.startFocus(minutes: 30) }
                    Button("1 hour") { store.startFocus(minutes: 60) }
                    Button("2 hours") { store.startFocus(minutes: 120) }
                    Button("Until I end it") { store.startFocus(minutes: nil) }
                } label: {
                    Label("Focus", systemImage: "moon")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .modifier(QuietMenu())
            }

            Spacer()

            Menu {
                Button("Settings…", action: openSettings)
                Button("Check for Updates") { updates.checkNow {} }
                Divider()
                Text("Lapse \(version)")
                Button("Quit Lapse", action: quit)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .modifier(QuietMenu())
            .help("More")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.tile.opacity(0.5))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }
}

/// Gives a borderless Menu the same padding and hover fill as QuietButtonStyle.
private struct QuietMenu: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .onHover { hovering = $0 }
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
                BarMark(x: .value("Day", d.id),
                        y: .value("Minutes", Double(d.seconds) / 60),
                        width: .ratio(0.5))
                    .foregroundStyle(color(for: d))
                    .cornerRadius(2.5)
            }
            if limitMin > 0 {
                RuleMark(y: .value("Limit", limitMin))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(Theme.faint)
            }
        }
        .chartYScale(domain: 0...max(limitMin * 1.1, maxMin * 1.05, 1))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: week.map(\.id)) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let day = week.first(where: { $0.id == id }) {
                        Text(day.label)
                            .font(.system(size: 10, weight: day.isToday ? .semibold : .regular))
                            .foregroundStyle(day.isToday ? Theme.ink : Theme.muted)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.35), value: week.map(\.seconds))
    }

    private func color(for d: Store.WeekDay) -> Color {
        if limitSeconds > 0, d.seconds > limitSeconds { return d.isToday ? Theme.over : Theme.over.opacity(0.5) }
        return d.isToday ? Theme.ink : Theme.ink.opacity(0.2)
    }
}
