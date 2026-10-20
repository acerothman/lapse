import AppKit
import Foundation

/// Asks GitHub whether a newer release exists. Automatic checks run on launch, then once a day.
@MainActor
final class UpdateCheck: ObservableObject {
    static let page = URL(string: "https://github.com/acerothman/lapse/releases/latest")!
    private static let api = URL(string: "https://api.github.com/repos/acerothman/lapse/releases/latest")!
    private static let lastKey = "lapse.lastUpdateCheck"
    private static let day: TimeInterval = 24 * 60 * 60

    /// Version string without a leading v, when a newer release is out.
    @Published private(set) var available: String?

    private var timer: Timer?

    func start() {
        Task { await checkIfDue() }
    }

    /// Menu and popover. Runs the check now. Opens the release page when nothing newer is waiting.
    func checkNow(showNotice: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            let newer = await refresh()
            if newer {
                showNotice()
            } else if available == nil {
                NSWorkspace.shared.open(Self.page)
            } else {
                showNotice()
            }
        }
    }

    func openDownload() {
        NSWorkspace.shared.open(Self.page)
    }

    private func checkIfDue() async {
        let last = UserDefaults.standard.object(forKey: Self.lastKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= Self.day {
            _ = await refresh()
        }
        scheduleNext()
    }

    private func scheduleNext() {
        timer?.invalidate()
        let last = UserDefaults.standard.object(forKey: Self.lastKey) as? Date ?? Date()
        let wait = max(60, Self.day - Date().timeIntervalSince(last))
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// True when a newer release is published.
    @discardableResult
    private func refresh() async -> Bool {
        guard let tag = await Self.latestTag() else { return available != nil }
        UserDefaults.standard.set(Date(), forKey: Self.lastKey)
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        if Self.isNewer(tag, than: current) {
            available = Self.display(tag)
            return true
        }
        available = nil
        return false
    }

    private static func display(_ tag: String) -> String {
        var text = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        return text
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let left = parts(remote)
        let right = parts(local)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let newer = index < left.count ? left[index] : 0
            let older = index < right.count ? right[index] : 0
            if newer != older { return newer > older }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        display(version).split(separator: ".").map { Int($0) ?? 0 }
    }

    private struct Release: Decodable {
        let tag_name: String
    }

    private static func latestTag() async -> String? {
        var request = URLRequest(url: api)
        request.setValue("Lapse", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let tag = release.tag_name.trimmingCharacters(in: .whitespacesAndNewlines)
            return tag.isEmpty ? nil : tag
        } catch {
            return nil
        }
    }
}
