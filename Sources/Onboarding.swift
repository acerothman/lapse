import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import UniformTypeIdentifiers

/// First-launch window. Shown once, and again from Settings.
struct OnboardingView: View {
    @ObservedObject var store: Store
    var onFinish: () -> Void
    @StateObject private var model: OnboardingModel

    static let size = NSSize(width: 600, height: 500)
    private static let lastStep = 4

    init(store: Store, startStep: Int = 0, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
        let registered = SMAppService.mainApp.status == .enabled
        let on = store.settings.didFinishOnboarding ? registered : true
        _model = StateObject(wrappedValue: OnboardingModel(launchOn: on, step: startStep))
    }

    private let columns = Array(repeating: GridItem(.flexible(minimum: 150), spacing: 8), count: 3)
    private let presets: [(String, Int)] = [
        ("30 min", 30),
        ("1 h", 60),
        ("1 h 30 min", 90),
        ("2 h", 120),
        ("3 h", 180),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case 0: welcome
                case 1: sitesStep
                case 2: appsStep
                case 3: limitStep
                default: permissionsStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.step == 0 ? .center : .topLeading)

            footer
        }
        .padding(.top, 40)
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.refreshNotifications()
            for app in store.settings.apps {
                _ = store.icon(forBundleID: app.id)
            }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 80, height: 80)
            Text("Welcome to Lapse")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.3)
                .padding(.top, 14)
            Text("Lapse shows how much time you spend on social media, right in your menu bar.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.top, 6)
            Label("Everything stays on your Mac.", systemImage: "lock")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
                .padding(.top, 18)
        }
        .padding(.bottom, 20)
    }

    private var sitesStep: some View {
        let x = store.settings.sites.first(where: { $0.id == "x.com" })
        return VStack(alignment: .leading, spacing: 0) {
            stepHeader("Which sites do you track?",
                       "Pick the ones you lose time on. You can change this later.")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.settings.sites) { site in
                    tile(name: site.name, icon: .site(site, favicon: store.favicons[site.id]), on: site.enabled) {
                        toggleSite(site.id)
                    }
                }
                addTile("Add a site") { model.adding = true }
            }

            if model.adding {
                HStack(spacing: 8) {
                    TextField("Add a site, like news.ycombinator.com", text: $model.draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitAdd)
                    Button("Add", action: commitAdd)
                        .disabled(model.draft.isEmpty)
                }
                .padding(.top, 10)
            }

            HStack(spacing: 6) {
                Text("\(store.settings.sites.filter(\.enabled).count) selected")
                if let x, x.enabled, x.countsFeedOnly {
                    Text("·")
                    Text("X counts only its feed. Change that in Settings.")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
            .padding(.top, 12)
        }
    }

    private var appsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader("Which apps do you track?",
                       "Time in these apps counts too. You can change this later.")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.settings.apps) { app in
                    tile(name: app.name, icon: .app(app, icon: store.appIcons[app.id]), on: app.enabled) {
                        toggleApp(app.id)
                    }
                }
                addTile("Add an app", action: addApp)
            }

            Text("\(store.settings.apps.filter(\.enabled).count) selected")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .padding(.top, 12)
        }
    }

    private var limitStep: some View {
        let minutes = store.settings.dailyLimitMinutes
        let limitBinding = Binding<Double>(
            get: { Double(store.settings.dailyLimitMinutes) },
            set: { store.settings.dailyLimitMinutes = GeneralPane.round15($0) })

        return VStack(alignment: .leading, spacing: 0) {
            stepHeader("Set a daily limit",
                       "You'll get a heads up, and a screen when you hit the limit.")

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.long(minutes * 60))
                    .font(Theme.number(40))
                    .tracking(-0.6)
                    .contentTransition(.numericText())
                    .animation(.default, value: minutes)
                Text("per day, all sites combined")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }

            Slider(value: limitBinding, in: 15...480) {
                EmptyView()
            } minimumValueLabel: {
                Text("15 min").font(.system(size: 11)).foregroundStyle(Theme.muted)
            } maximumValueLabel: {
                Text("8 h").font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 14)

            HStack(spacing: 6) {
                ForEach(presets, id: \.1) { label, value in
                    let selected = minutes == value
                    Button(label) { store.settings.dailyLimitMinutes = value }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(selected ? Color(nsColor: .windowBackgroundColor) : Theme.ink)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected ? Theme.ink : Theme.tile))
                }
            }
            .padding(.top, 12)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify me")
                        .font(.system(size: 13, weight: .medium))
                    Text("At 80% and when I hit the limit")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Toggle("Notify me", isOn: $store.settings.notificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
            .padding(.top, 24)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader("Two quick permissions",
                       "Your Mac will ask you to confirm each one.")

            VStack(spacing: 0) {
                permissionRow(symbol: "safari", title: "Browser access",
                              detail: "Lets Lapse see which site you're on in Safari, Chrome, Arc and others. It only keeps the site name.") {
                    if model.browserAllowed {
                        allowedMark
                    } else {
                        Button("Allow") { model.browserAllowed = Tracker.promptForBrowserAutomation() }
                    }
                }
                rowDivider
                permissionRow(symbol: "bell", title: "Notifications",
                              detail: "So you get a heads up near your limit.") {
                    if model.notificationsAllowed {
                        allowedMark
                    } else {
                        Button("Allow") { model.requestNotifications() }
                    }
                }
                rowDivider
                permissionRow(symbol: "power", title: "Open at login",
                              detail: "Starts when your Mac does.") {
                    Toggle("Open at login", isOn: $model.launchOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: model.launchOn) { on in model.applyLaunch(on) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5))

            HStack(alignment: .center, spacing: 12) {
                Text("Look for this in your menu bar")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                menuBarSample
            }
            .padding(.top, 18)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 52)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.step > 0 {
                Text("\(model.step) of \(Self.lastStep)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.faint)
            }
            Spacer()
            if model.step > 0 {
                Button("Back") { model.step -= 1 }
                    .controlSize(.large)
            }
            Button(primaryTitle) { advance() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 16)
    }

    private var primaryTitle: String {
        switch model.step {
        case 0: return "Get Started"
        case Self.lastStep: return "Start Tracking"
        default: return "Continue"
        }
    }

    private var allowedMark: some View {
        Label("Allowed", systemImage: "checkmark")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.muted)
    }

    /// The real ring from the menu bar, at 35%.
    private var menuBarSample: some View {
        HStack(spacing: 8) {
            Image(nsImage: StatusLabel.ring(fraction: 0.35))
                .renderingMode(.template)
                .foregroundStyle(.white)
            Text(Self.menuClock.string(from: Date()))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.85)))
    }

    private static let menuClock: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEhmm")
        return f
    }()

    // MARK: Pieces

    private func stepHeader(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.3)
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
    }

    private func tile(name: String, icon: ItemIcon.Source, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ItemIcon(source: icon, size: 22)
                Text(name)
                    .font(.system(size: 13, weight: on ? .medium : .regular))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(on ? Theme.ink : Theme.faint)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(on ? Theme.ink.opacity(0.85) : Theme.hairline, lineWidth: on ? 1.5 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? "Selected" : "Not selected")
    }

    private func addTile(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22, height: 22)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func permissionRow<Trailing: View>(symbol: String, title: String, detail: String,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.tile))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func toggleSite(_ id: String) {
        guard let i = store.settings.sites.firstIndex(where: { $0.id == id }) else { return }
        store.settings.sites[i].enabled.toggle()
    }

    private func toggleApp(_ id: String) {
        guard let i = store.settings.apps.firstIndex(where: { $0.id == id }) else { return }
        store.settings.apps[i].enabled.toggle()
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
        store.addApp(at: url)
    }

    private func commitAdd() {
        let raw = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        store.addSite(domain: raw)
        model.draft = ""
        model.adding = false
    }

    private func advance() {
        if model.step < Self.lastStep {
            model.step += 1
        } else {
            model.applyLaunch(model.launchOn)
            onFinish()
        }
    }
}

private final class OnboardingModel: ObservableObject {
    @Published var step: Int
    @Published var notificationsAllowed = false
    @Published var browserAllowed = false
    @Published var launchOn: Bool
    @Published var adding = false
    @Published var draft = ""

    init(launchOn: Bool, step: Int) {
        self.launchOn = launchOn
        self.step = step
    }

    func refreshNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized
            DispatchQueue.main.async { self.notificationsAllowed = allowed }
        }
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { self.notificationsAllowed = granted }
        }
    }

    func applyLaunch(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            let actual = SMAppService.mainApp.status == .enabled
            if launchOn != actual { launchOn = actual }
        }
    }
}
