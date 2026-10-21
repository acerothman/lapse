import AppKit
import SwiftUI

/// Calm full-screen screen shown when a limit is reached. Flat colors, no gradients.
@MainActor
final class SoftBlockController {
    private let store: Store
    private var window: NSWindow?
    private let model = SoftBlockModel()

    init(store: Store) {
        self.store = store
    }

    func sync() {
        if store.frictionRequest != nil || store.endEarlyVisible || store.blockTarget != nil || store.sessionLocksApps {
            hide()
            return
        }
        let reason = store.softBlockReason(currentID: store.currentSiteID)
        if let reason {
            model.reason = reason
            show()
        } else {
            hide()
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
        window.ignoresMouseEvents = false
        let root = SoftBlockView(model: model,
                                 snooze5: { [weak self] in self?.snooze(5) },
                                 snooze15: { [weak self] in self?.snooze(15) },
                                 turnOff: { [weak self] in self?.turnOff() })
        window.contentViewController = NSHostingController(rootView: root)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        self.window = window
    }

    private func hide() {
        window?.orderOut(nil)
        window = nil
    }

    private func snooze(_ minutes: Int) {
        store.snoozeSoftBlock(minutes: minutes)
        hide()
    }

    private func turnOff() {
        store.turnOffSoftBlockForToday()
        hide()
    }
}

final class SoftBlockModel: ObservableObject {
    @Published var reason: SoftBlockReason = .overall(used: 0, limit: 0)
}

struct SoftBlockView: View {
    @ObservedObject var model: SoftBlockModel
    let snooze5: () -> Void
    let snooze15: () -> Void
    let turnOff: () -> Void

    var body: some View {
        ZStack {
            Color.primary.opacity(0.32)
            VStack(spacing: 16) {
                Image(systemName: "hourglass")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(model.reason.title)
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(model.reason.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                VStack(spacing: 8) {
                    Button("Snooze 5 min", action: snooze5)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    Button("Snooze 15 min", action: snooze15)
                        .controlSize(.large)
                    Button("Turn off for today", action: turnOff)
                        .controlSize(.large)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .frame(width: 380)
            .background(Color(nsColor: .windowBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
