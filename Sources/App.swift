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
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSMenuDelegate {
    let store = Store.shared
    lazy var tracker = Tracker(store: store)
    let updates = UpdateCheck()
    private lazy var softBlock = SoftBlockController(store: store)
    private lazy var friction = FrictionController(store: store)
    private(set) var statusItem: NSStatusItem!
    let popover = NSPopover()
    private let statusMenu = NSMenu()
    private(set) var settingsController: SettingsWindowController?
    private(set) var onboardingWindow: NSWindow?
    private var observers = Set<AnyCancellable>()
    private var lastIdleRender = Date.distantPast
    private var idleShown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Scenes.applyAppearance()
        store.pruneOldDays()
        store.loadFavicons()
        for app in store.settings.apps { _ = store.icon(forBundleID: app.id) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = ""
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Lapse")
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusMenu.delegate = self
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

        tracker.gate = { [weak self] target in self?.friction.evaluate(target) ?? true }
        tracker.onTick = { [weak self] in
            self?.updateLabel()
            self?.softBlock.sync()
        }
        // Re-draw right away when settings, a pause or focus hours change, from here or from Shortcuts.
        store.$settings.dropFirst().map { _ in () }
            .merge(with: store.$state.dropFirst().map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updateLabel(force: true)
                self?.softBlock.sync()
            }
            .store(in: &observers)

        if Scenes.current != nil {
            Scenes.run(self)
            return
        }
        tracker.start()
        updates.start()
        Task { await LapseFocusFilter.sync() }
        if !store.settings.didFinishOnboarding {
            showOnboarding()
        }
    }

    // MARK: Status item

    @objc private func handleClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        statusItem.menu = statusMenu
        button.performClick(nil)
        statusItem.menu = nil
        button.action = #selector(handleClick(_:))
        button.target = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if store.isPaused {
            menu.addItem(item("Resume Tracking", #selector(resumeFromMenu(_:))))
        } else {
            let pause = NSMenuItem(title: "Pause Tracking", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, minutes) in [("15 Minutes", 15), ("30 Minutes", 30), ("1 Hour", 60)] {
                let i = item(title, #selector(pauseFromMenu(_:)))
                i.tag = minutes
                sub.addItem(i)
            }
            let tomorrow = item("Until Tomorrow", #selector(pauseFromMenu(_:)))
            tomorrow.tag = -1
            sub.addItem(tomorrow)
            let open = item("Until I Resume", #selector(pauseFromMenu(_:)))
            open.tag = 0
            sub.addItem(open)
            pause.submenu = sub
            menu.addItem(pause)
        }
        if store.isFocusHours() {
            menu.addItem(item("End Focus Hours", #selector(endFocusFromMenu(_:))))
        } else {
            let focus = NSMenuItem(title: "Start Focus Hours", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, minutes) in [("30 Minutes", 30), ("1 Hour", 60), ("2 Hours", 120), ("Until I End Them", 0)] {
                let i = item(title, #selector(startFocusFromMenu(_:)))
                i.tag = minutes
                sub.addItem(i)
            }
            focus.submenu = sub
            menu.addItem(focus)
        }
        menu.addItem(.separator())
        menu.addItem(item("Check for Updates", #selector(checkForUpdates(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettingsFromMenu(_:)), key: ","))
        menu.addItem(item("Quit Lapse", #selector(quitFromMenu(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func pauseFromMenu(_ sender: NSMenuItem) {
        switch sender.tag {
        case -1: store.pauseUntilTomorrow()
        case 0: store.pause(minutes: nil)
        default: store.pause(minutes: sender.tag)
        }
    }

    @objc private func resumeFromMenu(_ sender: Any?) { store.resume() }

    @objc private func startFocusFromMenu(_ sender: NSMenuItem) {
        store.startFocus(minutes: sender.tag == 0 ? nil : sender.tag)
    }

    @objc private func endFocusFromMenu(_ sender: Any?) { store.stopFocus() }

    @objc private func checkForUpdates(_ sender: Any?) {
        updates.checkNow { [weak self] in
            self?.showPopover()
        }
    }

    func showPopover() {
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

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { Links.handle(url, store: store) }
    }

    /// Active: redrawn every tick (1 s). Idle: the ring is redrawn at most every 30 s
    /// (or immediately on a state change) to keep CPU use low.
    func updateLabel(force: Bool = false) {
        guard let button = statusItem?.button else { return }
        let total = store.todayTotal
        let limit = store.limitSeconds

        if let until = store.pausedUntil {
            button.image = StatusLabel.paused()
            button.toolTip = until == .distantFuture ? "Lapse is paused" : "Lapse is paused until \(Fmt.time(until))"
            idleShown = false
            return
        }

        if let id = store.currentSiteID {
            let activeOver = store.isOver(id)
            let session = Fmt.session(Int(tracker.sessionSeconds))
            if let site = store.settings.sites.first(where: { $0.id == id }) {
                let glyph = StatusLabel.glyph(for: site, favicon: store.favicons[id])
                button.image = StatusLabel.active(glyph: glyph, text: session, over: activeOver,
                                                  appearance: button.effectiveAppearance)
                button.toolTip = "\(site.name), \(session) this visit, \(Fmt.long(total)) today"
                idleShown = false
                return
            } else if let app = store.settings.apps.first(where: { $0.id == id }) {
                let glyph: (image: NSImage, template: Bool)? = store.icon(forBundleID: id).map { ($0, false) }
                button.image = StatusLabel.active(glyph: glyph, text: session, over: activeOver,
                                                  appearance: button.effectiveAppearance)
                button.toolTip = "\(app.name), \(session) this visit, \(Fmt.long(total)) today"
                idleShown = false
                return
            }
        }
        showRing(button, total: total, limit: limit, force: force)
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

    // MARK: Windows

    func showSettings(tab: Int? = nil) {
        popover.performClose(nil)
        if settingsController == nil {
            settingsController = SettingsWindowController(store: store, updates: updates, showWelcome: { [weak self] in
                self?.showOnboarding()
            })
        }
        if let tab { settingsController?.select(tab: tab) }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    func showOnboarding(step: Int = 0) {
        let root = OnboardingView(store: store, startStep: step) { [weak self] in
            guard let self else { return }
            self.store.settings.didFinishOnboarding = true
            self.onboardingWindow?.close()
        }
        let host = NSHostingController(rootView: root)
        let size = OnboardingView.size
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
