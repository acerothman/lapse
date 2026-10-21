import AppKit
import SwiftUI

/// Hides or quits blocked apps during a focus, and covers a blocked site or app that is in front.
@MainActor
final class Blocker {
    private let store: Store
    private var hiddenPIDs = Set<pid_t>()
    private var quitURLs: [String: URL] = [:]
    private var quitPIDs = Set<pid_t>()
    private var locking = false
    private var window: NSWindow?

    init(store: Store) {
        self.store = store
    }

    func sync() {
        let nowLocking = store.sessionLocksApps
        if nowLocking {
            hideOrQuit()
            updateOverlay()
        } else if locking || !hiddenPIDs.isEmpty || !quitURLs.isEmpty {
            restore()
            if store.blockTarget != nil { store.blockTarget = nil }
            hideOverlay()
        }
        locking = nowLocking
    }

    func restore() {
        for pid in hiddenPIDs {
            NSRunningApplication(processIdentifier: pid)?.unhide()
        }
        hiddenPIDs.removeAll()
        quitPIDs.removeAll()
        let urls = Array(quitURLs.values)
        quitURLs.removeAll()
        for url in urls {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }

    private func hideOrQuit() {
        let hide = store.settings.session.hideApps
        let enabled = Set(store.settings.apps.filter(\.enabled).map(\.id))
        let selfID = Bundle.main.bundleIdentifier
        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier, enabled.contains(bid), bid != selfID else { continue }
            guard app.activationPolicy != .prohibited else { continue }
            if hide {
                if !app.isHidden {
                    app.hide()
                    hiddenPIDs.insert(app.processIdentifier)
                }
            } else if !quitPIDs.contains(app.processIdentifier) {
                if let url = app.bundleURL { quitURLs[bid] = url }
                app.terminate()
                quitPIDs.insert(app.processIdentifier)
            }
        }
    }

    private func updateOverlay() {
        guard !store.endEarlyVisible,
              let id = store.currentSiteID, store.isLocking(id) else {
            if store.blockTarget != nil { store.blockTarget = nil }
            hideOverlay()
            return
        }
        store.noteBlocked(id: id)
        if store.settings.apps.contains(where: { $0.id == id }) {
            _ = store.icon(forBundleID: id)
        }
        let target = BlockTarget(id: id, name: store.displayName(for: id))
        if store.blockTarget != target { store.blockTarget = target }
        showOverlay()
    }

    private func showOverlay() {
        guard window == nil else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // The block is always dark, so labels stay light even when the Mac is in light mode.
        window.appearance = NSAppearance(named: .darkAqua)
        let root = BlockedView(store: store,
                               backToWork: { [weak self] in self?.backToWork() },
                               notNow: { [weak self] in self?.notNow() })
        let host = NSHostingController(rootView: root)
        window.contentViewController = host
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        self.window = window
    }

    private func hideOverlay() {
        window?.orderOut(nil)
        window = nil
    }

    private func backToWork() {
        if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            finder.activate(options: [.activateAllWindows])
        }
        hideOverlay()
    }

    /// Leaving the block without ending the focus opens the hold, which is the only way out.
    private func notNow() {
        store.requestEndEarly()
    }
}

/// Near-black cover. Text uses the label colors of the dark appearance, not a hardcoded white.
struct BlockedView: View {
    @ObservedObject var store: Store
    let backToWork: () -> Void
    let notNow: () -> Void

    var body: some View {
        ZStack {
            BackdropBlur()
            Color(red: 11.0 / 255, green: 11.0 / 255, blue: 12.0 / 255).opacity(0.94)
            if let target = store.blockTarget, let session = store.activeSession {
                VStack(spacing: 12) {
                    targetIcon(target)
                        .padding(.bottom, 4)
                    Text("\(target.name) is off until \(Fmt.time(session.endsAt))")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Text(Fmt.session(store.remainingSeconds()))
                        .font(.system(size: 120, weight: .ultraLight))
                        .monospacedDigit()
                        .tracking(-1)
                        .foregroundStyle(.primary)
                    Text("You said \(session.plannedMinutes) minutes.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Button("Back to work", action: backToWork)
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(.top, 8)
                    Button("Not now.", action: notNow)
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func targetIcon(_ target: BlockTarget) -> some View {
        if let site = store.settings.sites.first(where: { $0.id == target.id }) {
            SiteIcon(site: site, favicon: store.favicons[site.id], size: 48)
        } else {
            AppIconView(image: store.appIcons[target.id], name: target.name, size: 48)
        }
    }
}

struct BackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Hold or a short reason before a focus ends early.
@MainActor
final class EndEarlyController {
    private let store: Store
    private var window: NSWindow?
    private let model = EndEarlyModel()
    private var timer: Timer?

    init(store: Store) {
        self.store = store
    }

    func sync() {
        guard store.endEarlyVisible, store.activeSession != nil else {
            hide()
            return
        }
        model.style = store.settings.frictionStyle
        model.total = Double(min(60, max(3, store.settings.frictionSeconds)))
        model.planned = store.activeSession?.plannedMinutes ?? store.settings.session.focusMinutes
        if window == nil {
            model.left = model.total
            model.holding = false
            model.draft = ""
            show()
        }
        startTimer()
    }

    private func show() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
                            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "End early"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let root = EndEarlyView(model: model,
                                cancel: { [weak self] in self?.cancel() },
                                finishReason: { [weak self] reason in self?.finish(reason: reason) })
        panel.contentViewController = NSHostingController(rootView: root)
        panel.center()
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        model.holding = false
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard model.style == .countdown else { return }
        if model.holding {
            model.left -= 0.05
            if model.left <= 0 { finish(reason: nil) }
        } else if model.left != model.total {
            model.left = model.total
        }
    }

    private func cancel() {
        store.cancelEndEarly()
        hide()
    }

    private func finish(reason: String?) {
        store.endSession(reason: reason)
        hide()
    }
}

final class EndEarlyModel: ObservableObject {
    @Published var style: FrictionStyle = .countdown
    @Published var total: Double = 10
    @Published var left: Double = 10
    @Published var holding = false
    @Published var draft = ""
    @Published var planned = 25
}

struct EndEarlyView: View {
    @ObservedObject var model: EndEarlyModel
    let cancel: () -> Void
    let finishReason: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("End early")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            if model.style == .countdown {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, 1 - model.left / max(model.total, 1))))
                        .stroke(Color.lapseAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(max(0, Int(ceil(model.left))))")
                        .font(.system(size: 56, weight: .light))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .frame(width: 144, height: 144)
                Text("Hold to end")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in model.holding = true }
                            .onEnded { _ in model.holding = false }
                    )
            } else {
                Text("Why end early?")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                TextField("Why this time?", text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                Button("End session") {
                    finishReason(model.draft)
                }
                .buttonStyle(.bordered)
                .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Button("Not now.", action: cancel)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("You said \(model.planned) minutes.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 320, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
