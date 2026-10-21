import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications

/// First-launch window. Three steps: the idea, the list, then permissions.
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

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case 0: intro
                case 1: pickList
                default: permissions
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(index == model.step ? Color.primary : Color.primary.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
                Spacer()
                Button(action: advance) {
                    Text(model.step == 2 ? "Start" : "Continue")
                }
                .buttonStyle(StartButtonStyle())
                .frame(width: 120)
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.refreshNotifications()
            for app in store.settings.apps { _ = store.icon(forBundleID: app.id) }
        }
    }

    private var intro: some View {
        Text("Lapse blocks the apps and sites you pick while you focus.")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pickList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blocked during focus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.settings.sites) { site in
                        row(title: site.name, icon: AnyView(SiteIcon(site: site, favicon: store.favicons[site.id], size: 16))) {
                            Toggle(site.name, isOn: siteEnabled(site.id))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                    ForEach(store.settings.apps) { app in
                        row(title: app.name, icon: AnyView(AppIconView(image: store.appIcons[app.id], name: app.name, size: 16))) {
                            Toggle(app.name, isOn: appEnabled(app.id))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            permissionRow(symbol: "safari", title: "Browser", detail: "Read the tab in front, so a blocked site can be covered.") {
                if model.browserAllowed {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.primary)
                } else {
                    Button("Allow") {
                        model.browserAllowed = Tracker.promptForBrowserAutomation()
                    }
                    .controlSize(.small)
                }
            }
            permissionRow(symbol: "bell", title: "Notifications", detail: "A limit, and the bell when a break starts.") {
                if model.notificationsAllowed {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.primary)
                } else {
                    Button("Allow", action: model.requestNotifications)
                        .controlSize(.small)
                }
            }
            permissionRow(symbol: "power", title: "Open at login", detail: "The timer is there when you sit down.") {
                Toggle("Open at login", isOn: $model.launchOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: model.launchOn) { on in model.applyLaunch(on) }
            }
            Spacer(minLength: 0)
        }
    }

    private func row<Trailing: View>(title: String, icon: AnyView, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            icon
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }

    private func permissionRow<Trailing: View>(symbol: String, title: String, detail: String,
                                               @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 4)
    }

    private func siteEnabled(_ id: String) -> Binding<Bool> {
        Binding {
            store.settings.sites.first { $0.id == id }?.enabled ?? false
        } set: { on in
            guard let i = store.settings.sites.firstIndex(where: { $0.id == id }) else { return }
            store.settings.sites[i].enabled = on
        }
    }

    private func appEnabled(_ id: String) -> Binding<Bool> {
        Binding {
            store.settings.apps.first { $0.id == id }?.enabled ?? false
        } set: { on in
            guard let i = store.settings.apps.firstIndex(where: { $0.id == id }) else { return }
            store.settings.apps[i].enabled = on
        }
    }

    private func advance() {
        if model.step < 2 {
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
