import AppKit

/// Finds, downloads and caches a site's logo for user-added sites.
/// Order: <link rel="apple-touch-icon"> (largest first), <link rel="icon"/"shortcut icon"> (largest first),
/// /favicon.ico, then Google's favicon service. Each candidate must decode with NSImage; anything
/// that doesn't (for example an SVG on systems that can't read it) is skipped.
enum FaviconFetcher {
    static let cacheDir: URL = {
        let dir = Store.dataDirectory.appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 15
        c.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Accept": "text/html,image/*,*/*;q=0.8",
        ]
        return URLSession(configuration: c)
    }()

    static func cacheURL(for domain: String) -> URL {
        cacheDir.appendingPathComponent(domain + ".png")
    }

    static func cachedImage(for domain: String) -> NSImage? {
        NSImage(contentsOf: cacheURL(for: domain))
    }

    static func removeCache(for domain: String) {
        try? FileManager.default.removeItem(at: cacheURL(for: domain))
    }

    /// Downloads the best icon, writes a 128 px PNG to the cache and returns it. Runs on the main actor
    /// (network waits suspend, they don't block) so NSImage drawing stays on the main thread.
    @MainActor
    static func fetch(domain: String) async -> NSImage? {
        for url in await candidates(for: domain) {
            guard let result = try? await session.data(from: url) else { continue }
            let (data, response) = result
            if data.isEmpty { continue }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { continue }
            guard let image = NSImage(data: data), image.isValid,
                  image.size.width > 0, image.size.height > 0,
                  let png = pngData(from: image, pixels: 128) else { continue }
            do { try png.write(to: cacheURL(for: domain), options: .atomic) } catch { }
            return NSImage(data: png)
        }
        return nil
    }

    // MARK: - Candidates

    private struct LinkIcon {
        let url: URL
        let priority: Int   // 0 = apple-touch-icon, 1 = icon / shortcut icon
        let size: Int
    }

    private static func candidates(for domain: String) async -> [URL] {
        var result: [URL] = []
        guard var base = URL(string: "https://\(domain)/") else { return [] }

        if let page = try? await session.data(from: base) {
            let (data, response) = page
            if let final = response.url { base = final }   // follow redirects, e.g. to www.
            let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            let icons = parseLinkIcons(html: html, base: base)
                .sorted { $0.priority != $1.priority ? $0.priority < $1.priority : $0.size > $1.size }
            result += icons.map(\.url)
        }

        if let ico = URL(string: "/favicon.ico", relativeTo: base)?.absoluteURL { result.append(ico) }
        if let host = base.host, host != domain,
           let ico = URL(string: "https://\(domain)/favicon.ico") { result.append(ico) }
        if let google = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128") {
            result.append(google)
        }

        var seen = Set<String>()
        return result.filter { seen.insert($0.absoluteString).inserted }
    }

    private static let linkRegex = try! NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: [.caseInsensitive])
    private static let attrRegex = try! NSRegularExpression(
        pattern: #"([a-zA-Z][a-zA-Z0-9_:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#, options: [])

    private static func parseLinkIcons(html: String, base: URL) -> [LinkIcon] {
        let ns = html as NSString
        var icons: [LinkIcon] = []
        for match in linkRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range)
            let attrs = attributes(of: tag)
            guard let rel = attrs["rel"]?.lowercased(), let rawHref = attrs["href"], !rawHref.isEmpty else { continue }
            let relWords = Set(rel.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init))

            let priority: Int
            if relWords.contains("apple-touch-icon") || relWords.contains("apple-touch-icon-precomposed") {
                priority = 0
            } else if relWords.contains("icon") {   // "icon" and "shortcut icon"; excludes "mask-icon"
                priority = 1
            } else {
                continue
            }

            let href = rawHref
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.hasPrefix("data:"),
                  let url = URL(string: href, relativeTo: base)?.absoluteURL,
                  url.scheme == "https" || url.scheme == "http" else { continue }

            // Apple touch icons with no sizes are conventionally 180 px.
            let size = largestSize(attrs["sizes"]) ?? (priority == 0 ? 180 : 0)
            icons.append(LinkIcon(url: url, priority: priority, size: size))
        }
        return icons
    }

    private static func attributes(of tag: String) -> [String: String] {
        let ns = tag as NSString
        var out: [String: String] = [:]
        for m in attrRegex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            var value = ""
            for i in 2...4 where m.range(at: i).location != NSNotFound {
                value = ns.substring(with: m.range(at: i))
                break
            }
            if out[key] == nil { out[key] = value }
        }
        return out
    }

    /// "16x16 32x32" -> 32, "any" -> 1024 (scalable), nil when absent.
    private static func largestSize(_ sizes: String?) -> Int? {
        guard let sizes = sizes?.lowercased(), !sizes.isEmpty else { return nil }
        if sizes.contains("any") { return 1024 }
        let values = sizes.split(separator: " ").compactMap { part -> Int? in
            guard let w = part.split(separator: "x").first else { return nil }
            return Int(w)
        }
        return values.max()
    }

    // MARK: - Rendering

    @MainActor
    private static func pngData(from image: NSImage, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)

        // Fit while keeping aspect ratio.
        let side = CGFloat(pixels)
        let scale = min(side / image.size.width, side / image.size.height)
        let w = image.size.width * scale, h = image.size.height * scale
        let rect = NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
