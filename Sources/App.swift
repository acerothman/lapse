import AppKit
import SwiftUI
import Combine
import UserNotifications

@main
@MainActor
enum LapseMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = Store.shared
    lazy var tracker = Tracker(store: store)
    private let updates = UpdateCheck()
    private lazy var softBlock = SoftBlockController(store: store)
    private lazy var friction = FrictionController(store: store)
    private lazy var blocker = Blocker(store: store)
    private lazy var endEarly = EndEarlyController(store: store)
    private let settingsRouter = SettingsRouter()
    private var lastAnnouncedPhase: SessionPhase?
    private var pauseItem: NSMenuItem?
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var statusMenu: NSMenu?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var settingsObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.pruneOldDays()
        store.loadFavicons()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Lapse")
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        installStatusMenu()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let root = PopoverView(store: store,
                               updates: updates,
                               openSettings: { [weak self] page in self?.showSettings(page) })
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        tracker.onTick = { [weak self] in
            self?.syncChrome()
            self?.refreshFocusIfDue()
        }
        NotificationCenter.default.addObserver(forName: .lapseChrome, object: nil, queue: .main) { [weak self] _ in
            guard let delegate = self else { return }
            Task { @MainActor in delegate.syncChrome() }
        }
        // Re-draw right away when the limit or sites change in Settings.
        settingsObserver = store.$settings.dropFirst().sink { [weak self] _ in
            guard let delegate = self else { return }
            Task { @MainActor in delegate.syncChrome() }
        }
        tracker.start()
        updates.start()
        Task { await FocusBridge.refresh() }
        if !store.settings.didFinishOnboarding {
            showOnboarding()
        }
        syncChrome()
    }

    private func installStatusMenu() {
        let menu = NSMenu()
        let check = NSMenuItem(title: "Check for updates", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        let pause = NSMenuItem(title: "Pause tracking", action: #selector(togglePause(_:)), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        pauseItem = pause
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit Lapse", action: #selector(quitFromMenu(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusMenu = menu
    }

    @objc private func handleClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover(sender)
        }
    }

    private var focusTicks = 0

    private func refreshFocusIfDue() {
        focusTicks += 1
        guard focusTicks >= 15 else { return }
        focusTicks = 0
        Task { await FocusBridge.refresh() }
    }

    private func showStatusMenu() {
        guard let menu = statusMenu, let button = statusItem.button else { return }
        pauseItem?.title = store.settings.trackingPaused ? "Resume tracking" : "Pause tracking"
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
        button.action = #selector(handleClick(_:))
        button.target = self
    }

    @objc private func togglePause(_ sender: Any?) {
        store.settings.trackingPaused.toggle()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updates.checkNow { [weak self] in
            self?.showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        showSettings()
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        blocker.restore()
        store.save()
    }

    private func syncChrome() {
        updateLabel()
        blocker.sync()
        endEarly.sync()
        friction.sync()
        softBlock.sync()
        announcePhaseIfNeeded()
    }

    private func announcePhaseIfNeeded() {
        let phase = store.activeSession?.phase
        let previous = lastAnnouncedPhase
        lastAnnouncedPhase = phase
        guard let phase, let previous, phase != previous, store.settings.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        switch phase {
        case .focus:
            content.title = "Focus"
            content.body = "\(store.settings.session.focusMinutes) minutes."
        case .shortBreak:
            content.title = "Break"
            content.body = "\(store.settings.session.shortBreakMinutes) minutes."
        case .longBreak:
            content.title = "Break"
            content.body = "\(store.settings.session.longBreakMinutes) minutes."
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Idle: a template timer symbol. During a session: a colored dot plus the countdown.
    /// The countdown is button title, so the menu bar colors the digits. The dot is not a template.
    private func updateLabel() {
        guard let button = statusItem?.button else { return }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        if let session = store.activeSession {
            let onBreak = session.phase != .focus
            let dot = StatusLabel.statusDot(onBreak: onBreak)
            dot.isTemplate = false
            button.image = dot
            button.imagePosition = .imageLeading
            button.title = Fmt.session(store.remainingSeconds())
            let title = onBreak ? "Break" : (session.pausedRemaining == nil ? "Focus" : "Paused")
            button.toolTip = "\(title), \(button.title)"
            button.setAccessibilityLabel("Lapse, \(title), \(button.title)")
            return
        }
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = StatusLabel.timerIcon()
        button.toolTip = store.settings.trackingPaused ? "Tracking is paused" : "Lapse"
        button.setAccessibilityLabel("Lapse")
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showSettings(_ page: SettingsPage = .general) {
        popover.performClose(nil)
        settingsRouter.tab = page
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(store: store, router: settingsRouter, showWelcome: { [weak self] in
                self?.showOnboarding()
            }))
            let w = NSWindow(contentViewController: host)
            w.title = "Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.backgroundColor = .windowBackgroundColor
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        let root = OnboardingView(store: store) { [weak self] in
            guard let self else { return }
            self.store.settings.didFinishOnboarding = true
            self.onboardingWindow?.close()
        }
        let host = NSHostingController(rootView: root)
        let size = NSSize(width: 480, height: 360)
        if onboardingWindow == nil {
            let w = NSWindow(contentViewController: host)
            w.title = "Welcome to Lapse"
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.backgroundColor = .windowBackgroundColor
            w.setContentSize(size)
            w.center()
            onboardingWindow = w
        } else {
            onboardingWindow?.contentViewController = host
            onboardingWindow?.setContentSize(size)
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }
}
