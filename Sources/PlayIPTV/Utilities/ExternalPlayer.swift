import AppKit
import Foundation

enum ExternalPlayerError: LocalizedError {
    case notInstalled(String)
    case unreadablePlaylist
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let name):
            return "\(name) is not installed. Install \(name), or switch back to the built-in player in Settings."
        case .unreadablePlaylist:
            return "Could not prepare the stream for VLC."
        case .launchFailed(let message):
            return message
        }
    }
}

@MainActor
enum ExternalPlayer {
    static let vlcBundleIdentifier = "org.videolan.vlc"
    static let iinaBundleIdentifier = "com.colliderli.iina"

    static var isVLCInstalled: Bool {
        vlcApplicationURL() != nil
    }

    static var isIINAInstalled: Bool {
        iinaApplicationURL() != nil
    }

    static func openInVLC(
        url: URL,
        title: String,
        userAgent: String?,
        referrer: String?,
        startPosition: Double?
    ) async throws {
        guard let appURL = vlcApplicationURL() else {
            throw ExternalPlayerError.notInstalled("VLC")
        }

        let playlistURL = try writePlaylist(
            url: url,
            title: title,
            userAgent: userAgent,
            referrer: referrer,
            startPosition: startPosition
        )

        try await openURLs([playlistURL], withApplicationAt: appURL)
    }

    static func openInIINA(
        url: URL,
        title: String,
        userAgent: String?,
        referrer: String?,
        startPosition: Double?
    ) async throws {
        guard let appURL = iinaApplicationURL() else {
            throw ExternalPlayerError.notInstalled("IINA")
        }

        let cli = appURL.appendingPathComponent("Contents/MacOS/iina-cli")
        guard FileManager.default.isExecutableFile(atPath: cli.path) else {
            try await openURLs([url], withApplicationAt: appURL)
            return
        }

        var arguments = ["--no-stdin"]
        if !title.isEmpty {
            arguments.append("--mpv-force-media-title=\(title)")
        }
        if let userAgent, !userAgent.isEmpty {
            arguments.append("--mpv-user-agent=\(userAgent)")
        }
        if let referrer, !referrer.isEmpty {
            arguments.append("--mpv-referrer=\(referrer)")
        }
        if let startPosition, startPosition > 1 {
            arguments.append(String(format: "--mpv-start=%.3f", startPosition))
        }
        if let proxy = iinaHTTPProxy() {
            arguments.append("--mpv-http-proxy=\(proxy)")
        }
        arguments.append(url.absoluteString)

        let process = Process()
        process.executableURL = cli
        process.arguments = arguments
        if let environment = iinaEnvironment() {
            process.environment = environment
        }
        do {
            try process.run()
        } catch {
            throw ExternalPlayerError.launchFailed(error.localizedDescription)
        }
    }

    private static func vlcApplicationURL() -> URL? {
        applicationURL(bundleIdentifier: vlcBundleIdentifier, appName: "VLC.app")
    }

    private static func iinaApplicationURL() -> URL? {
        applicationURL(bundleIdentifier: iinaBundleIdentifier, appName: "IINA.app")
    }

    private static func applicationURL(bundleIdentifier: String, appName: String) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }
        let candidates = [
            URL(fileURLWithPath: "/Applications").appendingPathComponent(appName),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications").appendingPathComponent(appName)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func openURLs(_ urls: [URL], withApplicationAt appURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: ExternalPlayerError.launchFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// HTTP proxies are an mpv option. SOCKS is passed through the process environment.
    private static func iinaHTTPProxy() -> String? {
        guard ProxySettings.shared.isActive, ProxySettings.shared.type == .http else { return nil }
        return proxyURLString(scheme: "http")
    }

    private static func iinaEnvironment() -> [String: String]? {
        guard ProxySettings.shared.isActive, ProxySettings.shared.type == .socks5,
              let proxy = proxyURLString(scheme: "socks5") else { return nil }
        var environment = ProcessInfo.processInfo.environment
        environment["ALL_PROXY"] = proxy
        environment["all_proxy"] = proxy
        return environment
    }

    private static func proxyURLString(scheme: String) -> String? {
        guard ProxySettings.shared.isActive, let port = ProxySettings.shared.portNumber else { return nil }
        let host = ProxySettings.shared.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return nil }
        var value = "\(scheme)://"
        let username = ProxySettings.shared.username
        if !username.isEmpty {
            value += "\(username):\(ProxySettings.shared.password)@"
        }
        value += "\(host):\(port)"
        return value
    }

    /// VLC applies per-item options from an XSPF playlist, including when the app is already running.
    private static func writePlaylist(
        url: URL,
        title: String,
        userAgent: String?,
        referrer: String?,
        startPosition: Double?
    ) throws -> URL {
        var options: [String] = []
        if let userAgent, !userAgent.isEmpty {
            options.append("http-user-agent=\(userAgent)")
        }
        if let referrer, !referrer.isEmpty {
            options.append("http-referrer=\(referrer)")
        }
        if let startPosition, startPosition > 1 {
            options.append(String(format: "start-time=%.3f", startPosition))
        }
        for option in ProxySettings.shared.vlcMediaOptions() {
            let trimmed = option.hasPrefix(":") ? String(option.dropFirst()) : option
            if !trimmed.isEmpty {
                options.append(trimmed)
            }
        }

        let optionXML = options.map { option in
            "\t\t\t\t<vlc:option>\(xmlEscape(option))</vlc:option>"
        }.joined(separator: "\n")

        let playlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <playlist xmlns="http://xspf.org/ns/0/" xmlns:vlc="http://www.videolan.org/vlc/playlist/ns/0/" version="1">
        \t<title>PlayIPTV</title>
        \t<trackList>
        \t\t<track>
        \t\t\t<location>\(xmlEscape(url.absoluteString))</location>
        \t\t\t<title>\(xmlEscape(title))</title>
        \t\t\t<extension application="http://www.videolan.org/vlc/playlist/0">
        \t\t\t\t<vlc:id>0</vlc:id>
        \(optionXML)
        \t\t\t</extension>
        \t\t</track>
        \t</trackList>
        \t<extension application="http://www.videolan.org/vlc/playlist/0">
        \t\t<vlc:item tid="0"/>
        \t</extension>
        </playlist>
        """

        let playlistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayIPTV-external.xspf")
        do {
            try playlist.write(to: playlistURL, atomically: true, encoding: .utf8)
        } catch {
            throw ExternalPlayerError.unreadablePlaylist
        }
        return playlistURL
    }

    private static func xmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
