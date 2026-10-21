import AppKit
import SwiftUI

/// The short pause screen before a tracked site or app opens.
/// The tracker asks `evaluate` every tick. While the screen is up, time does not count.
@MainActor
final class FrictionController {
    private let store: Store
    private var panel: NSPanel?
    private let model = FrictionModel()
    private var timer: Timer?
    /// Last time each site or app was in front and allowed. A visit within `grace` of that
    /// is the same visit, so the screen does not come back for a quick tab switch.
    private var passes: [String: Date] = [:]
    /// Held quietly (no screen) right after backing out, while the tab closes.
    private var holdUntil: [String: Date] = [:]
    static let grace: TimeInterval = 5 * 60

    init(store: Store) {
        self.store = store
    }

    var isShowing: Bool { panel != nil }

    /// True when time may count for this target.
    func evaluate(_ target: Target?) -> Bool {
        let now = Date()
        guard let target else {
            hide()
            return true
        }
        if let shown = model.target, shown != target { hide() }
        if let until = holdUntil[target.id], until > now { return false }
        if let last = passes[target.id], now.timeIntervalSince(last) < Self.grace {
            passes[target.id] = now
            return true
        }
        if model.target == target { return false }
        // The limit screen wins. Don't stack two screens.
        if store.softBlockReason(currentID: target.id) != nil {
            passes[target.id] = now
            return true
        }
        guard let friction = store.frictionNeeded(for: target.id) else {
            passes[target.id] = now
            return true
        }
        show(target, friction)
        return false
    }

    // MARK: Showing

    private func show(_ target: Target, _ friction: FrictionSettings) {
        model.target = target
        model.name = store.displayName(for: target.id)
        model.icon = store.iconSource(for: target.id)
        model.kind = friction.kind
        model.total = max(1, friction.seconds)
        model.remaining = friction.kind == .countdown ? max(1, friction.seconds) : 0
        model.reason = ""
        model.lastReason = store.lastReason(for: target.id)
        model.isApp = target.browser == nil

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let panel = KeyPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let root = FrictionScreen(model: model,
                                  open: { [weak self] in self?.open() },
                                  backOut: { [weak self] in self?.backOut() })
        panel.contentViewController = NSHostingController(rootView: root)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        self.panel = panel
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        guard model.kind == .countdown else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.model.remaining > 0 { self.model.remaining -= 1 }
                if self.model.remaining == 0 { self.timer?.invalidate() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        model.target = nil
    }

    // MARK: Actions

    private func open() {
        guard let target = model.target, model.canOpen else { return }
        let reason = model.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        store.record(FrictionEntry(date: Date(), itemID: target.id, name: model.name, kind: model.kind,
                                   reason: reason.isEmpty ? nil : reason, opened: true))
        passes[target.id] = Date()
        hide()
    }

    private func backOut() {
        guard let target = model.target else { return }
        let reason = model.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        store.record(FrictionEntry(date: Date(), itemID: target.id, name: model.name, kind: model.kind,
                                   reason: reason.isEmpty ? nil : reason, opened: false))
        holdUntil[target.id] = Date().addingTimeInterval(3)
        hide()
        if let browser = target.browser {
            if !Tracker.closeActiveTab(in: browser) {
                NSRunningApplication.runningApplications(withBundleIdentifier: browser).first?.hide()
            }
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: target.id).first?.hide()
        }
    }
}

/// Borderless panels can't take keyboard focus unless they say so.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class FrictionModel: ObservableObject {
    @Published var target: Target?
    @Published var name = ""
    @Published var icon: ItemIcon.Source?
    @Published var kind: FrictionKind = .countdown
    @Published var total = 10
    @Published var remaining = 10
    @Published var reason = ""
    @Published var lastReason: String?
    @Published var isApp = false

    var canOpen: Bool {
        switch kind {
        case .off: return true
        case .countdown: return remaining == 0
        case .reason: return reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
        }
    }
}

struct FrictionScreen: View {
    @ObservedObject var model: FrictionModel
    let open: () -> Void
    let backOut: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            FrictionCard(model: model, open: open, backOut: backOut)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FrictionCard: View {
    @ObservedObject var model: FrictionModel
    let open: () -> Void
    let backOut: () -> Void
    @FocusState private var fieldFocused: Bool

    var body: some View {
        OverlayCard(width: 400) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    if let icon = model.icon { ItemIcon(source: icon, size: 28) }
                    Text("Opening \(model.name)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                }

                if model.kind == .reason { reasonBody } else { countdownBody }

                HStack(spacing: 8) {
                    Button(action: backOut) {
                        HStack(spacing: 6) {
                            Text(model.isApp ? "Hide \(model.name)" : "Close Tab")
                            KeyCap(text: "esc")
                        }
                    }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
                    Spacer()
                    Button(action: open) {
                        HStack(spacing: 6) {
                            Text(openTitle).monospacedDigit()
                            if model.canOpen { KeyCap(text: "↩") }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(!model.canOpen)
                }
                .padding(.top, 22)
            }
        }
    }

    private var openTitle: String {
        if model.kind == .countdown && model.remaining > 0 { return "Open in \(model.remaining)" }
        return "Open \(model.name)"
    }

    private var countdownBody: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(model.remaining) / CGFloat(max(model.total, 1)))
                    .stroke(Theme.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: model.remaining)
                Text("\(model.remaining)")
                    .font(Theme.number(22))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: model.remaining)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.remaining > 0 ? "Give it \(model.total) seconds" : "Still want it?")
                    .font(.system(size: 20, weight: .semibold))
                Text(model.remaining > 0
                     ? "You asked for a pause before \(model.name). Decide when the timer runs out."
                     : "Go ahead, or close it. Either is fine.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 18)
    }

    private var reasonBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What's this for?")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 16)
            Text("Type why you're opening \(model.name). It goes in your log.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .padding(.top, 4)
            TextField("Replying to a message from Sam", text: $model.reason)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.tile))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(fieldFocused ? Theme.ink.opacity(0.35) : Theme.hairline, lineWidth: 1))
                .focused($fieldFocused)
                .onSubmit { if model.canOpen { open() } }
                .padding(.top, 14)
            if let last = model.lastReason {
                Text("Last time: \(last)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
                    .padding(.top, 6)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { fieldFocused = true }
        }
    }
}
