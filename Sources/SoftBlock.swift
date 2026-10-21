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
        let reason = store.softBlockReason(currentID: store.currentSiteID)
        if let reason, let id = store.currentSiteID {
            model.reason = reason
            model.icon = store.iconSource(for: id)
            model.usedToday = store.seconds(for: id)
            model.name = store.displayName(for: id)
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
    @Published var icon: ItemIcon.Source?
    @Published var name = ""
    @Published var usedToday = 0
}

struct SoftBlockView: View {
    @ObservedObject var model: SoftBlockModel
    let snooze5: () -> Void
    let snooze15: () -> Void
    let turnOff: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            SoftBlockCard(model: model, snooze5: snooze5, snooze15: snooze15, turnOff: turnOff)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SoftBlockCard: View {
    @ObservedObject var model: SoftBlockModel
    let snooze5: () -> Void
    let snooze15: () -> Void
    let turnOff: () -> Void

    var body: some View {
        OverlayCard(width: 380) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    if let icon = model.icon { ItemIcon(source: icon, size: 28) }
                    Text(model.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    Image(systemName: "hourglass")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.faint)
                }

                Text(model.reason.title)
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top, 18)
                Text(model.reason.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                VStack(spacing: 8) {
                    Button(action: snooze5) {
                        Text("Snooze 5 Minutes").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    HStack(spacing: 8) {
                        Button(action: snooze15) {
                            Text("Snooze 15 Minutes").frame(maxWidth: .infinity)
                        }
                        Button(action: turnOff) {
                            Text("Off for Today").frame(maxWidth: .infinity)
                        }
                    }
                    .controlSize(.large)
                }
                .padding(.top, 22)
            }
        }
    }
}
