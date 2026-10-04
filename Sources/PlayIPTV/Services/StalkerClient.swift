import CryptoKit
import Foundation

enum StalkerError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case invalidStream
    case requestRejected
    case networkError(String)
    case decodingError
    case portalMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Stalker portal URL"
        case .authenticationFailed, .requestRejected:
            return "Stalker portal authentication failed"
        case .invalidStream:
            return "The portal did not return a playable stream link"
        case .networkError(let message):
            return message
        case .decodingError:
            return "Unexpected response from the Stalker portal"
        case .portalMessage(let message):
            return message
        }
    }
}

enum StalkerLink {
    static let playbackUserAgent = "Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3"
    static let deviceHeader = "Model: MAG250; Link: Ethernet"

    static func portalURL(from raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "http://" + value
        }
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil else {
            return nil
        }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func normalizeMAC(_ raw: String) -> String? {
        let hex = raw.uppercased().filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        var parts: [String] = []
        var index = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(index, offsetBy: 2)
            parts.append(String(hex[index..<next]))
            index = next
        }
        return parts.joined(separator: ":")
    }

    static func playURL(type: String, cmd: String, series: String?) -> URL {
        var components = URLComponents()
        components.scheme = "stalker"
        components.host = "play"
        var items = [
            URLQueryItem(name: "type", value: type),
            URLQueryItem(name: "cmd", value: cmd)
        ]
        if let series, !series.isEmpty {
            items.append(URLQueryItem(name: "series", value: series))
        }
        components.queryItems = items
        return components.url ?? URL(string: "stalker://play")!
    }

    static func parse(_ url: URL) -> (type: String, cmd: String, series: String?)? {
        guard url.scheme?.lowercased() == "stalker",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let cmd = items.first(where: { $0.name == "cmd" })?.value,
              !cmd.isEmpty else {
            return nil
        }
        let type = items.first(where: { $0.name == "type" })?.value ?? "itv"
        let series = items.first(where: { $0.name == "series" })?.value
        return (type, cmd, series)
    }

    static func playableURL(from cmd: String) -> URL? {
        var value = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["ffmpeg ", "ffrt ", "ffrt2 ", "ffrt3 ", "auto ", "rtp ", "ext "]
        for _ in 0..<2 {
            let lower = value.lowercased()
            guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else { break }
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let range = value.range(of: "https://") ?? value.range(of: "http://") else { return nil }
        value = String(value[range.lowerBound...])
        if let space = value.firstIndex(of: " ") {
            value = String(value[..<space])
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard let url = URL(string: value), url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    static func apiCandidates(from portal: URL) -> [URL] {
        var path = portal.path
        if path.hasSuffix("/") { path.removeLast() }
        let fileName = (path as NSString).lastPathComponent
        if fileName.contains(".") && fileName != "load.php" && fileName != "portal.php" {
            path = (path as NSString).deletingLastPathComponent
            if path == "/" { path = "" }
        }

        if path.hasSuffix("load.php") || path.hasSuffix("portal.php") {
            return [url(portal, path: path)]
        }

        var paths: [String] = []
        if path.hasSuffix("/c") {
            let parent = String(path.dropLast(2))
            paths.append(parent + "/server/load.php")
            paths.append(parent + "/portal.php")
            paths.append(path + "/portal.php")
            if !parent.contains("stalker_portal") {
                paths.append("/stalker_portal/server/load.php")
            }
        } else if path.isEmpty {
            paths.append("/server/load.php")
            paths.append("/stalker_portal/server/load.php")
            paths.append("/portal.php")
            paths.append("/stalker_portal/portal.php")
            paths.append("/c/portal.php")
        } else {
            paths.append(path + "/server/load.php")
            paths.append(path + "/portal.php")
            paths.append(path + "/c/portal.php")
            if !path.contains("stalker_portal") {
                paths.append(path + "/stalker_portal/server/load.php")
            }
        }

        var urls: [URL] = []
        var seen = Set<String>()
        for candidate in paths {
            let url = url(portal, path: candidate)
            if seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02X", $0) }.joined()
    }

    static func sha1(_ value: String) -> String {
        Insecure.SHA1.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func url(_ portal: URL, path: String) -> URL {
        var components = URLComponents(url: portal, resolvingAgainstBaseURL: false)
        components?.path = path.isEmpty ? "/" : path
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? portal
    }
}

final class StalkerEpisodeStore {
    static let shared = StalkerEpisodeStore()
    private let lock = NSLock()
    private var storage: [String: [Episode]] = [:]

    func replace(sourceId: UUID, episodes: [String: [Episode]]) {
        lock.lock()
        defer { lock.unlock() }
        let prefix = sourceId.uuidString + ":"
        storage = storage.filter { !$0.key.hasPrefix(prefix) }
        for (seriesId, episodes) in episodes where !episodes.isEmpty {
            storage[prefix + seriesId] = episodes
        }
    }

    func episodes(sourceId: UUID, seriesId: String) -> [Episode]? {
        lock.lock()
        defer { lock.unlock() }
        return storage[sourceId.uuidString + ":" + seriesId]
    }

    func store(sourceId: UUID, seriesId: String, episodes: [Episode]) {
        guard !episodes.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        storage[sourceId.uuidString + ":" + seriesId] = episodes
    }
}

private struct StalkerSession {
    var apiURL: URL
    var token: String
    var random: String?
}

private final class StalkerSessionCache {
    static let shared = StalkerSessionCache()
    private let lock = NSLock()
    private var sessions: [String: StalkerSession] = [:]

    func session(for key: String) -> StalkerSession? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[key]
    }

    func save(_ session: StalkerSession, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        sessions[key] = session
    }

    func remove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeValue(forKey: key)
    }
}

struct StalkerVideoCatalog {
    var movies: [Channel] = []
    var series: [Channel] = []
    var episodes: [String: [Episode]] = [:]
}

final class StalkerClient {
    let portalURL: URL
    let mac: String
    let login: String?
    let password: String?
    let sourceName: String

    private let timezone: String
    private let serial: String
    private let deviceID: String
    private let hardwareVersion: String
    private var apiURL: URL?
    private var token: String?
    private var random: String?
    private let cacheKey: String

    init?(portal: String, mac: String, login: String?, password: String?, sourceName: String = "Stalker") {
        guard let portalURL = StalkerLink.portalURL(from: portal),
              let mac = StalkerLink.normalizeMAC(mac) else {
            return nil
        }
        self.portalURL = portalURL
        self.mac = mac
        let trimmedLogin = login?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.login = (trimmedLogin?.isEmpty == false) ? trimmedLogin : nil
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = (trimmedPassword?.isEmpty == false) ? trimmedPassword : nil
        self.sourceName = sourceName
        self.timezone = TimeZone.current.identifier
        self.serial = mac.replacingOccurrences(of: ":", with: "")
        self.deviceID = StalkerLink.sha256(mac)
        self.hardwareVersion = StalkerLink.sha1(mac)
        self.cacheKey = "\(portalURL.absoluteString)|\(mac)"
    }

    func authenticate() async throws {
        token = nil
        apiURL = nil
        random = nil
        StalkerSessionCache.shared.remove(cacheKey)

        var lastError: Error = StalkerError.authenticationFailed
        for candidate in StalkerLink.apiCandidates(from: portalURL) {
            do {
                let js = try await Self.get(
                    apiURL: candidate,
                    mac: mac,
                    portalURL: portalURL,
                    timezone: timezone,
                    token: nil,
                    sourceName: sourceName,
                    query: [
                        "type": "stb",
                        "action": "handshake",
                        "token": "",
                        "prehash": "false"
                    ]
                )
                guard let dict = js as? [String: Any],
                      let newToken = Self.string(dict, "token"),
                      !newToken.isEmpty else {
                    DebugLog.log(.warning, "Handshake at \(candidate.path) returned no token", source: sourceName, category: "Stalker")
                    continue
                }
                token = newToken
                apiURL = candidate
                random = Self.string(dict, "random")
                try await loadProfile()
                if let login, !login.isEmpty {
                    try await submitLogin()
                }
                StalkerSessionCache.shared.save(
                    StalkerSession(apiURL: candidate, token: newToken, random: random),
                    for: cacheKey
                )
                DebugLog.log(.success, "Authenticated via \(candidate.path)", source: sourceName, category: "Stalker")
                return
            } catch {
                token = nil
                apiURL = nil
                lastError = error
                DebugLog.log(
                    .warning,
                    "Handshake failed at \(candidate.path)",
                    source: sourceName,
                    category: "Stalker",
                    detail: DebugLog.describe(error)
                )
            }
        }
        throw lastError
    }

    func fetchLiveChannels() async throws -> [Channel] {
        try await ensureSession()
        do {
            return try await loadLiveChannels()
        } catch StalkerError.requestRejected, StalkerError.authenticationFailed {
            try await authenticate()
            return try await loadLiveChannels()
        }
    }

    func fetchVideoCatalog() async -> StalkerVideoCatalog {
        do {
            try await ensureSession()
        } catch {
            DebugLog.log(.warning, "VOD catalog skipped: \(DebugLog.describe(error))", source: sourceName, category: "Stalker")
            return StalkerVideoCatalog()
        }
        var catalog = StalkerVideoCatalog()
        if let items = try? await fetchModuleItems(type: "vod") {
            appendVideo(items, linkType: "vod", seriesOnly: false, into: &catalog)
        }
        if let items = try? await fetchModuleItems(type: "series") {
            appendVideo(items, linkType: "series", seriesOnly: true, into: &catalog)
        }
        return catalog
    }

    func episodesForSeries(id: String, playURL: URL) async -> [Episode] {
        do {
            try await ensureSession()
        } catch {
            return []
        }
        let preferred = StalkerLink.parse(playURL)?.type ?? "vod"
        let modules = preferred == "series" ? ["series", "vod"] : ["vod", "series"]
        for module in modules {
            let query = [
                "movie_id": id,
                "season_id": "0",
                "episode_id": "0",
                "category": "*",
                "p": "1"
            ]
            guard let js = try? await request(type: module, action: "get_ordered_list", query: query) else { continue }
            let items = Self.extractItems(js)
            let match = items.first { Self.string($0, "id") == id } ?? (items.count == 1 ? items.first : nil)
            if let match, let episodes = Self.episodes(from: match, linkType: module), !episodes.isEmpty {
                return episodes
            }
            if let dict = js as? [String: Any],
               Self.string(dict, "id") == id,
               let episodes = Self.episodes(from: dict, linkType: module),
               !episodes.isEmpty {
                return episodes
            }
        }
        return []
    }

    func resolveLink(type: String, cmd: String, series: String?) async throws -> URL {
        try await ensureSession()
        let types: [String]
        if type == "itv" {
            types = ["itv"]
        } else if type == "series" {
            types = ["series", "vod"]
        } else {
            types = ["vod"]
        }

        var lastError: Error = StalkerError.invalidStream
        var refreshed = false
        for linkType in types {
            do {
                if let url = try await createLink(type: linkType, cmd: cmd, series: series) {
                    return url
                }
            } catch StalkerError.requestRejected, StalkerError.authenticationFailed {
                if !refreshed {
                    refreshed = true
                    try await authenticate()
                    if let url = try await createLink(type: linkType, cmd: cmd, series: series) {
                        return url
                    }
                }
            } catch {
                lastError = error
            }
        }
        if let direct = StalkerLink.playableURL(from: cmd) {
            return direct
        }
        throw lastError
    }

    private func ensureSession() async throws {
        if apiURL != nil, token != nil { return }
        if let cached = StalkerSessionCache.shared.session(for: cacheKey) {
            apiURL = cached.apiURL
            token = cached.token
            random = cached.random
            return
        }
        try await authenticate()
    }

    private func loadProfile() async throws {
        let metrics: [String: String] = [
            "mac": mac,
            "sn": serial,
            "model": "MAG250",
            "type": "STB",
            "uid": "",
            "random": random ?? ""
        ]
        let metricsData = try JSONSerialization.data(withJSONObject: metrics)
        let metricsJSON = String(data: metricsData, encoding: .utf8) ?? "{}"
        let version = "ImageDescription: 0.2.18-r23-254; ImageDate: Wed Oct 31 15:22:54 EET 2018; PORTAL version: 5.5.0; API Version: JS API version: 343; STB API version: 146; Player Engine version: 0x58c"
        let js = try await request(type: "stb", action: "get_profile", query: [
            "hd": "1",
            "ver": version,
            "num_banks": "2",
            "sn": serial,
            "stb_type": "MAG250",
            "client_type": "STB",
            "image_version": "218",
            "video_out": "hdmi",
            "device_id": deviceID,
            "device_id2": deviceID,
            "signature": "",
            "auth_second_step": "0",
            "hw_version": "1.7-BD-00",
            "not_valid_token": "0",
            "metrics": metricsJSON,
            "hw_version_2": hardwareVersion,
            "timestamp": String(Int(Date().timeIntervalSince1970)),
            "api_signature": "262",
            "prehash": "false"
        ])
        if let dict = js as? [String: Any] {
            if let status = Self.string(dict, "status"), status == "0" || status == "2" {
                if let message = Self.string(dict, "block_msg", "msg") {
                    throw StalkerError.portalMessage(message)
                }
                throw StalkerError.authenticationFailed
            }
        }
    }

    private func submitLogin() async throws {
        guard let login else { return }
        let js = try await request(type: "stb", action: "do_auth", query: [
            "login": login,
            "password": password ?? "",
            "device_id": deviceID,
            "device_id2": deviceID
        ])
        if let dict = js as? [String: Any], Self.string(dict, "status") == "0" {
            throw StalkerError.authenticationFailed
        }
    }

    private func loadLiveChannels() async throws -> [Channel] {
        if let items = try? await singleList(type: "itv", action: "get_all_channels"), !items.isEmpty {
            return Self.dedupe(items).compactMap { Self.makeLiveChannel($0, portal: portalURL) }
        }
        let items = try await fetchModuleItems(type: "itv")
        return Self.dedupe(items).compactMap { Self.makeLiveChannel($0, portal: portalURL) }
    }

    private func singleList(type: String, action: String) async throws -> [[String: Any]] {
        let js = try await request(type: type, action: action)
        let info = Self.pageInfo(js)
        if info.total > info.items.count {
            return []
        }
        return info.items
    }

    private func fetchModuleItems(type: String) async throws -> [[String: Any]] {
        let listKey = type == "itv" ? "genre" : "category"
        if let items = try? await fetchAllPages(type: type, action: "get_ordered_list", extra: [listKey: "*"]),
           !items.isEmpty {
            return items
        }

        let categoryAction = type == "itv" ? "get_genres" : "get_categories"
        let categories = Self.extractItems(try await request(type: type, action: categoryAction))
        var all: [[String: Any]] = []
        for category in categories {
            guard let id = Self.string(category, "id", "category_id"), id != "*", !id.isEmpty else { continue }
            if let items = try? await fetchAllPages(type: type, action: "get_ordered_list", extra: [listKey: id]) {
                all.append(contentsOf: items)
            }
        }
        return all
    }

    private func fetchAllPages(type: String, action: String, extra: [String: String]) async throws -> [[String: Any]] {
        let first = try await request(type: type, action: action, query: extra.merging(["p": "1"]) { _, new in new })
        let info = Self.pageInfo(first)
        if info.items.isEmpty || info.items.count >= info.total {
            return Self.dedupe(info.items)
        }

        let pageSize = max(min(info.pageSize, info.items.count), 1)
        let pageCount = min(400, max(1, Int(ceil(Double(info.total) / Double(pageSize)))))
        if pageCount == 1 {
            return Self.dedupe(info.items)
        }

        var pages = Array(repeating: [[String: Any]](), count: pageCount)
        pages[0] = info.items
        let anchor = Self.string(info.items[0], "id")
        guard let credentials = currentCredentials else { throw StalkerError.authenticationFailed }

        var nextPage = 2
        var stopped = false
        while nextPage <= pageCount && !stopped {
            let end = min(nextPage + 3, pageCount)
            let batch = Array(nextPage...end)
            let fetched: [Int: [[String: Any]]] = try await withThrowingTaskGroup(of: (Int, [[String: Any]]).self) { group in
                for page in batch {
                    group.addTask {
                        var query = extra
                        query["type"] = type
                        query["action"] = action
                        query["p"] = String(page)
                        let js = try await Self.get(
                            apiURL: credentials.apiURL,
                            mac: credentials.mac,
                            portalURL: credentials.portalURL,
                            timezone: credentials.timezone,
                            token: credentials.token,
                            sourceName: credentials.sourceName,
                            query: query
                        )
                        return (page, Self.pageInfo(js).items)
                    }
                }
                var collected: [Int: [[String: Any]]] = [:]
                for try await (page, items) in group {
                    collected[page] = items
                }
                return collected
            }

            for page in batch {
                let items = fetched[page] ?? []
                if items.isEmpty {
                    stopped = true
                    break
                }
                if let anchor, let first = items.first, Self.string(first, "id") == anchor {
                    stopped = true
                    break
                }
                pages[page - 1] = items
            }
            nextPage = end + 1
        }

        return Self.dedupe(pages.flatMap { $0 })
    }

    private func appendVideo(_ items: [[String: Any]], linkType: String, seriesOnly: Bool, into catalog: inout StalkerVideoCatalog) {
        var seenMovies = Set(catalog.movies.map(\.streamId))
        var seenSeries = Set(catalog.series.map(\.streamId))
        for item in items {
            guard let id = Self.string(item, "id") else { continue }
            let episodes = Self.episodes(from: item, linkType: linkType) ?? []
            let isSeries = seriesOnly || Self.itemIsSeries(item) || !episodes.isEmpty
            if isSeries {
                if seenSeries.insert(id).inserted,
                   let channel = Self.makeVideoChannel(item, portal: portalURL, linkType: linkType, isSeries: true) {
                    catalog.series.append(channel)
                }
                if catalog.episodes[id] == nil, !episodes.isEmpty {
                    catalog.episodes[id] = episodes
                }
            } else if !seriesOnly {
                guard seenMovies.insert(id).inserted else { continue }
                if let channel = Self.makeVideoChannel(item, portal: portalURL, linkType: linkType, isSeries: false) {
                    catalog.movies.append(channel)
                }
            }
        }
    }

    private func createLink(type: String, cmd: String, series: String?) async throws -> URL? {
        let js = try await request(type: type, action: "create_link", query: [
            "cmd": cmd,
            "series": series ?? "",
            "forced_storage": "undefined",
            "disable_ad": "0",
            "download": "0",
            "force_ch_link_check": "0"
        ])
        guard let command = Self.commandString(js) else { return nil }
        return StalkerLink.playableURL(from: command)
    }

    private struct Credentials: Sendable {
        var apiURL: URL
        var token: String
        var mac: String
        var portalURL: URL
        var timezone: String
        var sourceName: String
    }

    private var currentCredentials: Credentials? {
        guard let apiURL, let token else { return nil }
        return Credentials(apiURL: apiURL, token: token, mac: mac, portalURL: portalURL, timezone: timezone, sourceName: sourceName)
    }

    private func request(type: String, action: String, query: [String: String] = [:]) async throws -> Any {
        guard let credentials = currentCredentials else { throw StalkerError.authenticationFailed }
        var merged = query
        merged["type"] = type
        merged["action"] = action
        return try await Self.get(
            apiURL: credentials.apiURL,
            mac: credentials.mac,
            portalURL: credentials.portalURL,
            timezone: credentials.timezone,
            token: credentials.token,
            sourceName: credentials.sourceName,
            query: merged
        )
    }

    private static func get(apiURL: URL, mac: String, portalURL: URL, timezone: String, token: String?, sourceName: String, query: [String: String]) async throws -> Any {
        guard var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            throw StalkerError.invalidURL
        }
        var items: [URLQueryItem] = []
        if let type = query["type"] {
            items.append(URLQueryItem(name: "type", value: type))
        }
        if let action = query["action"] {
            items.append(URLQueryItem(name: "action", value: action))
        }
        for key in query.keys.sorted() where key != "type" && key != "action" {
            items.append(URLQueryItem(name: key, value: query[key]))
        }
        items.append(URLQueryItem(name: "JsHttpRequest", value: "1-xml"))
        components.queryItems = items
        guard let url = components.url else { throw StalkerError.invalidURL }

        let action = query["action"] ?? "request"
        let typeName = query["type"] ?? "stb"
        let page = query["p"]
        let verbose = page == nil || page == "1" || action == "handshake" || action == "get_profile" || action == "do_auth" || action == "create_link"
        if verbose {
            DebugLog.log(.info, "GET \(typeName)/\(action) \(DebugLog.redact(url))", source: sourceName, category: "Stalker")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(StalkerLink.playbackUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(StalkerLink.deviceHeader, forHTTPHeaderField: "X-User-Agent")
        request.setValue(portalURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        var cookie = "mac=\(mac); stb_lang=en; timezone=\(timezone)"
        if let token, !token.isEmpty {
            cookie += "; token=\(token)"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await NetworkSession.shared.data(for: request)
        } catch {
            DebugLog.log(.error, DebugLog.describe(error), source: sourceName, category: "Stalker", detail: "\(typeName)/\(action)")
            throw StalkerError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw StalkerError.networkError("No response from the portal")
        }
        if verbose {
            DebugLog.log(.info, "HTTP \(http.statusCode) · \(data.count) bytes for \(typeName)/\(action)", source: sourceName, category: "Stalker")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            DebugLog.log(.error, "HTTP \(http.statusCode) for \(typeName)/\(action)", source: sourceName, category: "Stalker", detail: DebugLog.preview(data))
            throw StalkerError.authenticationFailed
        }
        guard (200...299).contains(http.statusCode) else {
            DebugLog.log(.error, "HTTP \(http.statusCode) for \(typeName)/\(action)", source: sourceName, category: "Stalker", detail: DebugLog.preview(data))
            throw StalkerError.networkError("Portal returned HTTP \(http.statusCode)")
        }
        guard let json = parseJSON(data) as? [String: Any] else {
            DebugLog.log(.error, "Could not parse \(typeName)/\(action) JSON", source: sourceName, category: "Stalker", detail: DebugLog.preview(data))
            throw StalkerError.decodingError
        }
        if json["js"] == nil || json["js"] is NSNull {
            throw StalkerError.decodingError
        }
        if let rejected = json["js"] as? Bool, rejected == false {
            DebugLog.log(.warning, "Portal rejected \(typeName)/\(action)", source: sourceName, category: "Stalker", detail: DebugLog.preview(data))
            throw StalkerError.requestRejected
        }
        if let rejected = json["js"] as? Int, rejected == 0 {
            DebugLog.log(.warning, "Portal rejected \(typeName)/\(action)", source: sourceName, category: "Stalker", detail: DebugLog.preview(data))
            throw StalkerError.requestRejected
        }
        if let rejected = json["js"] as? String, rejected.isEmpty {
            DebugLog.log(.warning, "Portal rejected \(typeName)/\(action)", source: sourceName, category: "Stalker", detail: DebugLog.preview(data))
            throw StalkerError.requestRejected
        }
        if let dict = json["js"] as? [String: Any], let error = dict["error"] as? String {
            let lowered = error.lowercased()
            if lowered.contains("auth") || lowered.contains("token") {
                DebugLog.log(.error, error, source: sourceName, category: "Stalker", detail: "\(typeName)/\(action)")
                throw StalkerError.authenticationFailed
            }
        }
        return json["js"] as Any
    }

    private static func parseJSON(_ data: Data) -> Any? {
        var payload = data
        if let start = payload.firstIndex(of: UInt8(ascii: "{")), start > payload.startIndex {
            payload = payload.suffix(from: start)
        }
        if payload.starts(with: [0xEF, 0xBB, 0xBF]) {
            payload = payload.dropFirst(3)
        }
        if let object = try? JSONSerialization.jsonObject(with: payload) {
            return object
        }
        for encoding in [String.Encoding.windowsCP1251, .isoLatin1] {
            if let text = String(data: payload, encoding: encoding),
               let utf8 = text.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: utf8) {
                return object
            }
        }
        return nil
    }

    private static func makeLiveChannel(_ item: [String: Any], portal: URL) -> Channel? {
        guard let id = string(item, "id") else { return nil }
        let name = string(item, "name", "title", "o_name") ?? "Channel \(id)"
        let cmd = command(from: item) ?? "ffrt http://localhost/ch/\(id)"
        return Channel(
            streamId: id,
            name: name,
            logoUrl: absoluteURL(string(item, "logo", "stream_icon", "pic"), portal: portal),
            streamUrl: StalkerLink.playURL(type: "itv", cmd: cmd, series: nil),
            categoryId: "0",
            groupTitle: nil,
            isSeries: false
        )
    }

    private static func makeVideoChannel(_ item: [String: Any], portal: URL, linkType: String, isSeries: Bool) -> Channel? {
        guard let id = string(item, "id") else { return nil }
        let name = string(item, "name", "title", "o_name") ?? (isSeries ? "Series \(id)" : "Movie \(id)")
        let cmd = command(from: item) ?? "/media/file_\(id).mpg"
        return Channel(
            streamId: id,
            name: name,
            logoUrl: absoluteURL(string(item, "screenshot_uri", "pic", "cover", "logo"), portal: portal),
            streamUrl: StalkerLink.playURL(type: linkType, cmd: cmd, series: nil),
            categoryId: "0",
            groupTitle: nil,
            isSeries: isSeries
        )
    }

    private static func itemIsSeries(_ item: [String: Any]) -> Bool {
        if let flag = string(item, "is_series")?.lowercased(), ["1", "true", "yes"].contains(flag) {
            return true
        }
        return false
    }

    private static func episodes(from item: [String: Any], linkType: String) -> [Episode]? {
        guard let seriesId = string(item, "id"), let rawSeries = item["series"] else { return nil }
        let cmd = command(from: item) ?? "/media/file_\(seriesId).mpg"
        let entries = seriesEntries(rawSeries)
        guard !entries.isEmpty else { return nil }

        var episodes: [Episode] = []
        for (index, entry) in entries.enumerated() {
            switch entry {
            case .token(let token):
                let (season, episode) = parseToken(token, fallback: index + 1)
                episodes.append(makeEpisode(
                    seriesId: seriesId,
                    season: season,
                    episode: episode,
                    title: nil,
                    cmd: cmd,
                    seriesParam: token,
                    linkType: linkType
                ))
            case .object(let dict):
                let season = intValue(dict["season_id"]) ?? intValue(dict["season"]) ?? intValue(dict["season_num"]) ?? 1
                let episode = intValue(dict["series_number"]) ?? intValue(dict["episode_num"]) ?? intValue(dict["episode"]) ?? intValue(dict["series"]) ?? (index + 1)
                let param = string(dict, "series_number", "series", "id") ?? String(episode)
                let episodeCmd = command(from: dict) ?? cmd
                episodes.append(makeEpisode(
                    seriesId: seriesId,
                    season: max(season, 1),
                    episode: max(episode, 1),
                    title: string(dict, "name", "title"),
                    cmd: episodeCmd,
                    seriesParam: param,
                    linkType: linkType
                ))
            }
        }
        guard !episodes.isEmpty else { return nil }
        return episodes.sorted { ($0.seasonNum, $0.episodeNum) < ($1.seasonNum, $1.episodeNum) }
    }

    private static func makeEpisode(seriesId: String, season: Int, episode: Int, title: String?, cmd: String, seriesParam: String, linkType: String) -> Episode {
        Episode(
            id: "\(seriesId):\(season):\(episode):\(seriesParam)",
            episodeNum: episode,
            seasonNum: season,
            title: title,
            streamUrl: StalkerLink.playURL(type: linkType, cmd: cmd, series: seriesParam),
            containerExtension: "ts"
        )
    }

    private enum SeriesEntry {
        case token(String)
        case object([String: Any])
    }

    private static func seriesEntries(_ value: Any, expandCounts: Bool = true) -> [SeriesEntry] {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "0" || trimmed == "[]" { return [] }
            if (trimmed.hasPrefix("[") || trimmed.hasPrefix("{")),
               let data = trimmed.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) {
                return seriesEntries(parsed, expandCounts: expandCounts)
            }
            if trimmed.contains(","), !trimmed.contains(" ") {
                let parts = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if !parts.isEmpty, parts.allSatisfy({ Int($0) != nil }) {
                    return parts.map { .token($0) }
                }
            }
            if let range = expandRange(trimmed) {
                return range.map { .token($0) }
            }
            if expandCounts, let number = Int(trimmed), number > 1 {
                return (1...min(number, 500)).map { .token(String($0)) }
            }
            if Int(trimmed) != nil || trimmed.contains(":") {
                return [.token(trimmed)]
            }
            return []
        }
        if expandCounts, let number = value as? Int, number > 0 {
            if number == 1 { return [.token("1")] }
            return (1...min(number, 500)).map { .token(String($0)) }
        }
        if let array = value as? [Any] {
            var entries: [SeriesEntry] = []
            for element in array {
                if let text = element as? String {
                    entries.append(contentsOf: seriesEntries(text, expandCounts: false))
                } else if let number = element as? Int {
                    entries.append(.token(String(number)))
                } else if let number = element as? NSNumber {
                    entries.append(.token(number.stringValue))
                } else if let dict = element as? [String: Any] {
                    entries.append(.object(dict))
                }
            }
            return entries
        }
        return []
    }

    private static func expandRange(_ token: String) -> [String]? {
        let parts = token.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = Int(parts[0]),
              let end = Int(parts[1]),
              start > 0,
              end >= start,
              end - start < 500 else {
            return nil
        }
        return (start...end).map(String.init)
    }

    private static func parseToken(_ token: String, fallback: Int) -> (Int, Int) {
        if token.contains(":") {
            let parts = token.split(separator: ":")
            let season = Int(parts.first ?? "") ?? 1
            let episode = Int(parts.dropFirst().first ?? "") ?? fallback
            return (max(season, 1), max(episode, 1))
        }
        if let number = Int(token) {
            return (1, max(number, 1))
        }
        return (1, max(fallback, 1))
    }

    private static func command(from item: [String: Any]) -> String? {
        if let cmd = string(item, "cmd"), !cmd.isEmpty { return cmd }
        if let commands = item["cmds"] as? [[String: Any]] {
            for command in commands {
                if let url = string(command, "url", "cmd"), !url.isEmpty { return url }
            }
        }
        return nil
    }

    private static func commandString(_ js: Any) -> String? {
        if let text = js as? String, !text.isEmpty { return text }
        if let dict = js as? [String: Any] {
            return string(dict, "cmd", "url")
        }
        return nil
    }

    private static func extractItems(_ js: Any) -> [[String: Any]] {
        if let items = js as? [[String: Any]] { return items }
        if let items = js as? [Any] { return items.compactMap { $0 as? [String: Any] } }
        if let dict = js as? [String: Any] {
            if let data = dict["data"] { return extractItems(data) }
            if dict["id"] != nil { return [dict] }
        }
        return []
    }

    private static func pageInfo(_ js: Any) -> (total: Int, pageSize: Int, items: [[String: Any]]) {
        let items = extractItems(js)
        guard let dict = js as? [String: Any] else {
            return (items.count, max(items.count, 1), items)
        }
        let total = intValue(dict["total_items"]) ?? items.count
        let pageSize = intValue(dict["max_page_items"]) ?? max(items.count, 1)
        return (total, max(pageSize, 1), items)
    }

    private static func dedupe(_ items: [[String: Any]]) -> [[String: Any]] {
        var seen = Set<String>()
        var result: [[String: Any]] = []
        for item in items {
            guard let id = string(item, "id") else {
                result.append(item)
                continue
            }
            if seen.insert(id).inserted {
                result.append(item)
            }
        }
        return result
    }

    private static func absoluteURL(_ raw: String?, portal: URL) -> URL? {
        guard var raw, !raw.isEmpty else { return nil }
        raw = raw.replacingOccurrences(of: "\\/", with: "/")
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if raw.hasPrefix("//") {
            return URL(string: "\(portal.scheme ?? "http"):\(raw)")
        }
        guard var components = URLComponents(url: portal, resolvingAgainstBaseURL: false) else { return nil }
        components.query = nil
        components.fragment = nil
        if raw.hasPrefix("/") {
            components.path = raw
        } else {
            var base = components.path
            if !base.hasSuffix("/") { base += "/" }
            components.path = base + raw
        }
        return components.url
    }

    private static func string(_ item: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let text = item[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let number = item[key] as? Int {
                return String(number)
            } else if let number = item[key] as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as Double:
            return Int(number)
        case let text as String:
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }
}
