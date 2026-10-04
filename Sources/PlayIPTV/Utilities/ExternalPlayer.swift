import AppKit
import Foundation

enum ExternalPlayerError: LocalizedError {
    case notInstalled
    case unreadablePlaylist
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "VLC is not installed. Install VLC, or switch back to the built-in player in Settings."
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

    static var isVLCInstalled: Bool {
        applicationURL() != nil
    }

    static func openInVLC(
        url: URL,
        title: String,
        userAgent: String?,
        referrer: String?,
        startPosition: Double?
    ) async throws {
        guard let appURL = applicationURL() else {
            throw ExternalPlayerError.notInstalled
        }

        let playlistURL = try writePlaylist(
            url: url,
            title: title,
            userAgent: userAgent,
            referrer: referrer,
            startPosition: startPosition
        )

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(
                [playlistURL],
                withApplicationAt: appURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(throwing: ExternalPlayerError.launchFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func applicationURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: vlcBundleIdentifier) {
            return url
        }
        let candidates = [
            URL(fileURLWithPath: "/Applications/VLC.app"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/VLC.app")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
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
