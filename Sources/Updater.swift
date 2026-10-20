import AppKit
import Sparkle

/// Sparkle 2. Checks automatically, and from the Check for updates menu item.
@MainActor
final class Updater: NSObject {
    private var controller: SPUStandardUpdaterController?

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
    }

    func check() {
        controller?.checkForUpdates(nil)
    }
}
