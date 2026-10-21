import Foundation
import Security

/// lapse:// links. Shortcuts can call them with "Open URLs", and they work on every build.
/// macOS only lets apps signed by a developer team use App Intents, so the ad-hoc release
/// builds rely on these for Shortcuts and Focus automations.
///
///   lapse://focus/start?minutes=60   lapse://focus/stop
///   lapse://pause?minutes=30         lapse://resume
///   lapse://limit?minutes=90         lapse://limit?minutes=20&site=reddit.com
///
/// Leave out minutes to keep focus hours on, or stay paused, until stopped.
enum Links {
    @MainActor
    @discardableResult
    static func handle(_ url: URL, store: Store) -> Bool {
        guard url.scheme?.lowercased() == "lapse" else { return false }
        let path = ([url.host ?? ""] + url.pathComponents)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty && $0 != "/" }
            .joined(separator: "/")
        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            query[item.name.lowercased()] = item.value
        }
        let minutes = query["minutes"].flatMap { Int($0) }

        switch path {
        case "focus", "focus/start":
            store.startFocus(minutes: minutes.map { max(1, $0) })
        case "focus/stop", "focus/end":
            store.stopFocus()
        case "pause":
            store.pause(minutes: minutes.map { max(1, $0) })
        case "resume":
            store.resume()
        case "limit":
            guard let minutes else { return false }
            if let name = query["site"] ?? query["app"] ?? query["item"] {
                guard let id = itemID(matching: name, in: store) else { return false }
                store.setItemLimit(id, minutes: minutes)
            } else {
                store.settings.dailyLimitMinutes = min(max(minutes, 1), 24 * 60)
            }
        default:
            return false
        }
        return true
    }

    /// Accepts a site id, any of its domains, a bundle id, or a name.
    static func itemID(matching raw: String, in store: Store) -> String? {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let site = store.settings.sites.first(where: { $0.id == key || $0.domains.contains(key) || $0.name.lowercased() == key }) {
            return site.id
        }
        if let app = store.settings.apps.first(where: { $0.id.lowercased() == key || $0.name.lowercased() == key }) {
            return app.id
        }
        return nil
    }
}

/// Whether this copy of Lapse is signed by a developer team. macOS only connects Shortcuts
/// actions and Focus filters to team-signed apps; ad-hoc builds use the links above.
enum Signing {
    static let teamID: String? = {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    static var hasTeam: Bool { teamID != nil }
}
