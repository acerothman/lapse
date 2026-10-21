import AppKit
import SwiftUI

struct FrictionRequest: Equatable {
    var targetID: String
    var name: String
    var style: FrictionStyle
    var seconds: Int
}

/// Pause screen shown before a tracked site or app is counted.
@MainActor
final class FrictionController {
    private let store: Store
    private var window: NSWindow?
    private let model = FrictionModel()
    private var timer: Timer?

    init(store: Store) {
        self.store = store
    }

    func sync() {
        guard let request = store.frictionRequest else {
            hide()
            return
        }
        let changed = model.request?.targetID != request.targetID || model.request?.style != request.style
        model.request = request
        if changed {
            model.remaining = request.seconds
            model.draft = ""
        }
        show()
        if request.style == .countdown {
            startTimer()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func show() {
        guard window == nil else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hasShadow = false
        let root = FrictionView(model: model,
                                open: { [weak self] in self?.open() },
                                notNow: { [weak self] in self?.notNow() })
        window.contentViewController = NSHostingController(rootView: root)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        self.window = window
    }

    private func hide() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor in controller.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard model.request?.style == .countdown else { return }
        if model.remaining > 0 { model.remaining -= 1 }
    }

    private func open() {
        let reason = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        store.passFriction(reason: reason.isEmpty ? nil : reason)
        hide()
    }

    private func notNow() {
        store.declineFriction()
        hide()
    }
}

final class FrictionModel: ObservableObject {
    @Published var request: FrictionRequest?
    @Published var remaining = 10
    @Published var draft = ""
}

struct FrictionView: View {
    @ObservedObject var model: FrictionModel
    let open: () -> Void
    let notNow: () -> Void

    var body: some View {
        ZStack {
            Color.primary.opacity(0.35)
            if let request = model.request {
                card(request)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func card(_ request: FrictionRequest) -> some View {
        VStack(spacing: 16) {
            Image(systemName: request.style == .countdown ? "hourglass" : "text.quote")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.secondary)
            if request.style == .countdown {
                Text("\(model.remaining)")
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
                Text("Wait a moment")
                    .font(.system(size: 20, weight: .semibold))
                Text("Opening \(request.name).")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button("Open anyway", action: open)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.remaining > 0)
                    .keyboardShortcut(.defaultAction)
            } else {
                Text("Why \(request.name)?")
                    .font(.system(size: 20, weight: .semibold))
                Text("A short note is enough.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("Why this time?", text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                Button("Continue", action: open)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            Button("Not now", action: notNow)
                .controlSize(.large)
        }
        .padding(28)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
