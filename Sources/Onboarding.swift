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

    init(store: Store, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
        let registered = SMAppService.mainApp.status == .enabled
        let on = store.settings.didFinishOnboarding ? registered : true
        _model = StateObject(wrappedValue: OnboardingModel(launchOn: on))
    }

    private let columns = Array(repeating: GridItem(.flexible(minimum: 108), spacing: 8), count: 4)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.step == 0 ? .center : .top)

            footer
        }
        .padding(.top, 36)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(width: 560, height: 512)
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
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
            Text("Welcome to Lapse")
                .font(.system(size: 22, weight: .semibold))
            Text("Lapse shows how much time you spend on social media, right in your menu bar.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.system(size: 10))
                Text("Everything stays on your Mac.")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }

    private var sitesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader("Which sites do you track?",
                       "Pick the ones you lose time on. You can change this later.")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(store.settings.sites) { site in
                    siteTile(site)
                }
                addTile
            }
            .padding(.top, 6)
            .padding(.trailing, 4)

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

            Text("\(store.settings.sites.filter(\.enabled).count) selected")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        }
    }

    private var appsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            stepHeader("Which apps do you track?",
                       "Time in these apps counts too. You can change this later.")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(store.settings.apps) { app in
                    appTile(app)
                }
                addAppTile
            }
            .padding(.top, 6)
            .padding(.trailing, 4)

            Text("\(store.settings.apps.filter(\.enabled).count) selected")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        }
    }

    private var limitStep: some View {
        let minutes = store.settings.dailyLimitMinutes
        let limitBinding = Binding<Double>(
            get: { Double(store.settings.dailyLimitMinutes) },
            set: { store.settings.dailyLimitMinutes = Int($0) })

        return VStack(alignment: .leading, spacing: 0) {
            stepHeader("Set a daily limit",
                       "You'll get a heads up, and a screen when you hit the limit.")

            VStack(spacing: 2) {
                Text(Fmt.long(minutes * 60))
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                Text("per day, all sites combined")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04)))

            HStack(spacing: 8) {
                Text("15 min")
                Slider(value: limitBinding, in: 15...480, step: 15)
                Text("8 h")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 14)

            HStack(spacing: 8) {
                ForEach(presets, id: \.1) { label, value in
                    let selected = minutes == value
                    Button(label) { store.settings.dailyLimitMinutes = value }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1)
                        )
                }
            }
            .padding(.top, 12)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notify me")
                        .font(.system(size: 13, weight: .medium))
                    Text("At 80% and when I hit the limit")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Notify me", isOn: $store.settings.notificationsEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04)))
            .padding(.top, 16)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            stepHeader("Two quick permissions",
                       "Your Mac will ask you to confirm each one.")

            permissionRow(symbol: "safari", tint: .blue, title: "Browser access",
                          detail: "Lets Lapse see which site you're on in Safari, Chrome, Arc and others. It only keeps the site name.") {
                if model.browserAllowed {
                    allowedMark
                } else {
                    Button("Allow") { model.browserAllowed = Tracker.promptForBrowserAutomation() }
                        .controlSize(.small)
                }
            }

            permissionRow(symbol: "bell.fill", tint: .red, title: "Notifications",
                          detail: "So you get a heads up near your limit.") {
                if model.notificationsAllowed {
                    allowedMark
                } else {
                    Button("Allow") { model.requestNotifications() }
                        .controlSize(.small)
                }
            }

            permissionRow(symbol: "power", tint: .secondary, title: "Open at login",
                          detail: "Starts when your Mac does.") {
                Toggle("Open at login", isOn: $model.launchOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: model.launchOn) { on in model.applyLaunch(on) }
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Look for this in your menu bar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                menuBarSample
            }
            .padding(.top, 6)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i == model.step ? Color.primary : Color.primary.opacity(0.22))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if model.step > 0 {
                Button("Back") { model.step -= 1 }
            }
            Button(primaryTitle) { advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 12)
    }

    private var primaryTitle: String {
        switch model.step {
        case 0: return "Get Started"
        case 4: return "Start Tracking"
        default: return "Continue"
        }
    }

    private var allowedMark: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .semibold))
            Text("Allowed")
                .font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
    }

    private var menuBarSample: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white, lineWidth: 1.4)
                Circle()
                    .trim(from: 0, to: 0.35)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            Text(Self.menuClock.string(from: Date()))
                .font(.system(size: 12))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.86)))
    }

    private static let menuClock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()

    // MARK: Pieces

    private func stepHeader(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 14)
    }

    private func siteTile(_ site: SiteConfig) -> some View {
        let on = site.enabled
        return Button {
            toggle(site.id)
        } label: {
            HStack(spacing: 6) {
                mark(for: site)
                Text(site.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.12),
                                  lineWidth: on ? 1.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if on {
                    ZStack {
                        Circle().fill(Color.accentColor)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 14, height: 14)
                    .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var addTile: some View {
        Button {
            model.adding = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, height: 16)
                Text("Add a site")
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func appTile(_ app: AppConfig) -> some View {
        let on = app.enabled
        return Button {
            toggleApp(app.id)
        } label: {
            HStack(spacing: 6) {
                AppIconView(image: store.appIcons[app.id], name: app.name, size: 16)
                Text(app.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(on ? Color.accentColor : Color.primary.opacity(0.12),
                                  lineWidth: on ? 1.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if on {
                    ZStack {
                        Circle().fill(Color.accentColor)
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 14, height: 14)
                    .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var addAppTile: some View {
        Button(action: addApp) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16, height: 16)
                Text("Add an app")
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func mark(for site: SiteConfig) -> some View {
        if let name = site.icon,
           let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(glyphColor(site.colorHex))
                .frame(width: 16, height: 16)
        } else if let favicon = store.favicons[site.id] {
            Image(nsImage: favicon)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        } else {
            Text(String(site.name.prefix(1)))
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 16, height: 16)
        }
    }

    private func permissionRow<Trailing: View>(symbol: String, tint: Color, title: String, detail: String,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func glyphColor(_ hex: String) -> Color {
        lightHex(hex) ? .black : Color(hex: hex)
    }

    private func lightHex(_ hex: String) -> Bool {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF)
        let g = Double((v >> 8) & 0xFF)
        let b = Double(v & 0xFF)
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.72
    }

    private func toggle(_ id: String) {
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
        if model.step < 4 {
            model.step += 1
        } else {
            model.applyLaunch(model.launchOn)
            onFinish()
        }
    }
}

private final class OnboardingModel: ObservableObject {
    @Published var step = 0
    @Published var notificationsAllowed = false
    @Published var browserAllowed = false
    @Published var launchOn: Bool
    @Published var adding = false
    @Published var draft = ""

    init(launchOn: Bool) {
        self.launchOn = launchOn
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
