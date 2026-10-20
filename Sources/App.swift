import AppKit
import SwiftUI
import Combine

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
    let store = Store()
    lazy var tracker = Tracker(store: store)
    private let updates = UpdateCheck()
    private lazy var softBlock = SoftBlockController(store: store)
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var statusMenu: NSMenu?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var settingsObserver: AnyCancellable?
    private var lastIdleRender = Date.distantPast
    private var idleShown = false

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
        updateLabel(force: true)

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let root = PopoverView(store: store,
                               updates: updates,
                               openSettings: { [weak self] in self?.showSettings() },
                               quit: { NSApp.terminate(nil) })
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        tracker.onTick = { [weak self] in
            self?.updateLabel()
            self?.softBlock.sync()
        }
        // Re-draw right away when the limit or sites change in Settings.
        settingsObserver = store.$settings.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateLabel(force: true)
                self?.softBlock.sync()
            }
        }
        tracker.start()
        updates.start()
        if !store.settings.didFinishOnboarding {
            showOnboarding()
        }
    }

    private func installStatusMenu() {
        let menu = NSMenu()
        let check = NSMenuItem(title: "Check for updates", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
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

    private func showStatusMenu() {
        guard let menu = statusMenu, let button = statusItem.button else { return }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
        button.action = #selector(handleClick(_:))
        button.target = self
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
        store.save()
    }

    /// Active: redrawn every tick (1 s). Idle: the ring is redrawn at most every 30 s
    /// (or immediately on a state change) to keep CPU use low.
    private func updateLabel(force: Bool = false) {
        guard let button = statusItem?.button else { return }
        let total = store.todayTotal
        let limit = store.limitSeconds
        let over = limit == 0 || total >= limit

        if let id = store.currentSiteID {
            let itemOver = store.itemLimitSeconds(for: id).map { (store.today.seconds[id] ?? 0) >= $0 } ?? false
            let activeOver = over || itemOver
            if let site = store.settings.sites.first(where: { $0.id == id }) {
                let glyph = StatusLabel.glyph(for: site, favicon: store.favicons[id])
                button.image = StatusLabel.active(glyph: glyph,
                                                  text: Fmt.session(Int(tracker.sessionSeconds)),
                                                  over: activeOver,
                                                  appearance: button.effectiveAppearance)
                button.toolTip = "\(site.name), \(Fmt.session(Int(tracker.sessionSeconds))) this visit, \(Fmt.long(total)) today"
                idleShown = false
            } else if let app = store.settings.apps.first(where: { $0.id == id }) {
                let icon = store.icon(forBundleID: id)
                let glyph: (image: NSImage, template: Bool)? = icon.map { ($0, false) }
                button.image = StatusLabel.active(glyph: glyph,
                                                  text: Fmt.session(Int(tracker.sessionSeconds)),
                                                  over: activeOver,
                                                  appearance: button.effectiveAppearance)
                button.toolTip = "\(app.name), \(Fmt.session(Int(tracker.sessionSeconds))) this visit, \(Fmt.long(total)) today"
                idleShown = false
            } else {
                showRing(button, total: total, limit: limit, force: force)
            }
        } else {
            showRing(button, total: total, limit: limit, force: force)
        }
    }

    private func showRing(_ button: NSStatusBarButton, total: Int, limit: Int, force: Bool) {
            let now = Date()
            guard force || !idleShown || now.timeIntervalSince(lastIdleRender) >= 30 else { return }
            let fraction = limit == 0 ? 1.0 : Double(total) / Double(max(limit, 1))
            button.image = StatusLabel.ring(fraction: fraction)
            let cap = limit == 0 ? "no time during focus hours" : Fmt.long(limit)
            button.toolTip = "\(Fmt.long(total)) of \(cap) today"
            lastIdleRender = now
            idleShown = true
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

    func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(store: store, showWelcome: { [weak self] in
                self?.showOnboarding()
            }))
            let w = NSWindow(contentViewController: host)
            w.title = "Lapse Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
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
        let size = NSSize(width: 560, height: 512)
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
