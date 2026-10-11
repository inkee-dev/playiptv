import Foundation

enum EPGDiscovery {
    /// Guide link advertised on the playlist's `#EXTM3U` header (`url-tvg`, `x-tvg-url`, or `tvg-url`).
    /// If the header has none, an Xtream `get.php` playlist URL is turned into `xmltv.php` on the same server.
    static func m3uGuideURL(content: String, playlistURL: URL?) -> (url: URL, reason: String)? {
        if let header = m3uHeaderLine(in: content) {
            let attributes = attributes(in: header)
            for key in ["url-tvg", "x-tvg-url", "tvg-url"] {
                guard let raw = attributes[key] else { continue }
                let urls = guideURLs(in: raw)
                if let first = urls.first {
                    let reason = urls.count > 1 ? "playlist \(key) (1 of \(urls.count))" : "playlist \(key)"
                    return (first, reason)
                }
            }
        }
        if let playlistURL, let derived = xtreamGuideURL(fromPlaylist: playlistURL) {
            return (derived, "Xtream playlist URL")
        }
        return nil
    }

    /// The single XMLTV file Xtream panels serve beside `player_api.php`.
    static func xtreamGuideURL(server: String, username: String, password: String) -> URL? {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let pass = password.trimmingCharacters(in: .whitespacesAndNewlines)
        var raw = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !user.isEmpty, !pass.isEmpty else { return nil }
        if !raw.contains("://") {
            raw = "http://" + raw
        }
        guard var components = URLComponents(string: raw), components.host != nil else { return nil }
        components.path = directoryPath(components.path) + "/xmltv.php"
        components.queryItems = [
            URLQueryItem(name: "username", value: user),
            URLQueryItem(name: "password", value: pass)
        ]
        components.fragment = nil
        return components.url
    }

    /// A few Stalker portals include a guide URL on the profile. Most do not.
    static func stalkerGuideURL(in profile: [String: Any]) -> URL? {
        let keys = ["epg_url", "xmltv_url", "xmltv", "epg_link", "tv_guide_url", "guide_url"]
        for key in keys {
            guard let text = profile[key] as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil else { continue }
            return url
        }
        return nil
    }

    private static func xtreamGuideURL(fromPlaylist playlist: URL) -> URL? {
        guard let components = URLComponents(url: playlist, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }
        let file = (components.path as NSString).lastPathComponent.lowercased()
        guard file == "get.php" || file == "player_api.php" else { return nil }
        func query(_ names: String...) -> String? {
            for name in names {
                if let value = items.first(where: { $0.name.lowercased() == name })?.value,
                   !value.isEmpty {
                    return value
                }
            }
            return nil
        }
        guard let user = query("username", "user"), let pass = query("password", "pass") else { return nil }
        var xml = components
        xml.path = directoryPath(components.path) + "/xmltv.php"
        xml.queryItems = [
            URLQueryItem(name: "username", value: user),
            URLQueryItem(name: "password", value: pass)
        ]
        xml.fragment = nil
        return xml.url
    }

    private static func directoryPath(_ path: String) -> String {
        var directory = path
        if directory.hasSuffix("/") { directory.removeLast() }
        let file = (directory as NSString).lastPathComponent.lowercased()
        if file == "player_api.php" || file == "get.php" || file == "xmltv.php" {
            directory = (directory as NSString).deletingLastPathComponent
        }
        if directory == "/" { directory = "" }
        return directory
    }

    private static func m3uHeaderLine(in content: String) -> String? {
        var scanned = 0
        for rawLine in content.split(whereSeparator: \.isNewline) {
            scanned += 1
            if scanned > 40 { break }
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            let upper = line.uppercased()
            if upper.hasPrefix("#EXTINF") { break }
            if upper.hasPrefix("#EXTM3U") { return line }
        }
        return nil
    }

    private static func attributes(in line: String) -> [String: String] {
        var attributes: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "([A-Za-z0-9-]+)=(?:\"([^\"]*)\"|'([^']*)')") else {
            return attributes
        }
        let range = NSRange(line.startIndex..., in: line)
        for match in regex.matches(in: line, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: line) else { continue }
            let key = line[keyRange].lowercased()
            let valueRange = Range(match.range(at: 2), in: line) ?? Range(match.range(at: 3), in: line)
            guard let valueRange else { continue }
            attributes[key] = String(line[valueRange])
        }
        return attributes
    }

    private static func guideURLs(in raw: String) -> [URL] {
        raw.split(separator: ",").compactMap { piece in
            let trimmed = piece
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil else { return nil }
            return url
        }
    }
}
