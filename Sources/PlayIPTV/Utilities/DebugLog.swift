import Foundation
import Combine

enum DebugLogLevel: String, CaseIterable, Identifiable {
    case info = "Info"
    case success = "OK"
    case warning = "Warn"
    case error = "Error"
    
    var id: String { rawValue }
    
    var symbolName: String {
        switch self {
        case .info: return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

struct DebugLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: DebugLogLevel
    let source: String?
    let category: String
    let message: String
    let detail: String?
}

@MainActor
final class DebugLog: ObservableObject {
    static let shared = DebugLog()
    
    @Published private(set) var entries: [DebugLogEntry] = []
    
    private let maxEntries = 500
    
    private init() {}
    
    func add(_ level: DebugLogLevel, _ message: String, source: String? = nil, category: String = "App", detail: String? = nil) {
        entries.append(DebugLogEntry(
            timestamp: Date(),
            level: level,
            source: source,
            category: category,
            message: message,
            detail: detail
        ))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        let prefix = source.map { "[\($0)] " } ?? ""
        print("DEBUG: \(level.rawValue.uppercased()) \(category) \(prefix)\(message)")
        if let detail, !detail.isEmpty {
            print("DEBUG:   \(detail)")
        }
    }
    
    func info(_ message: String, source: String? = nil, category: String = "App", detail: String? = nil) {
        add(.info, message, source: source, category: category, detail: detail)
    }
    
    func success(_ message: String, source: String? = nil, category: String = "App", detail: String? = nil) {
        add(.success, message, source: source, category: category, detail: detail)
    }
    
    func warning(_ message: String, source: String? = nil, category: String = "App", detail: String? = nil) {
        add(.warning, message, source: source, category: category, detail: detail)
    }
    
    func error(_ message: String, source: String? = nil, category: String = "App", detail: String? = nil) {
        add(.error, message, source: source, category: category, detail: detail)
    }
    
    func clear() {
        entries.removeAll()
    }
    
    func copyText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return entries.map { entry in
            let time = formatter.string(from: entry.timestamp)
            let source = entry.source.map { " [\($0)]" } ?? ""
            let detail = entry.detail.map { "\n    \($0)" } ?? ""
            return "\(time) \(entry.level.rawValue.uppercased()) \(entry.category)\(source) \(entry.message)\(detail)"
        }.joined(separator: "\n")
    }
    
    /// Safe to call from any isolation domain.
    nonisolated static func log(_ level: DebugLogLevel, _ message: String, source: String? = nil, category: String = "App", detail: String? = nil) {
        Task { @MainActor in
            shared.add(level, message, source: source, category: category, detail: detail)
        }
    }
    
    nonisolated static func redact(_ url: URL) -> String {
        redact(url.absoluteString)
    }
    
    nonisolated static func redact(_ raw: String) -> String {
        var result = raw
        if var components = URLComponents(string: raw) {
            if let items = components.queryItems {
                components.queryItems = items.map { item in
                    let name = item.name.lowercased()
                    if name == "password" || name == "pass" || name == "pwd" {
                        return URLQueryItem(name: item.name, value: "•••")
                    }
                    return item
                }
            }
            if let redacted = components.string {
                result = redacted
            }
        }
        // Path-style credentials: /live/user/pass/id.ts
        let pattern = #"/(live|movie|series)/([^/]+)/([^/]+)/"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "/$1/$2/•••/")
        }
        return result
    }
    
    nonisolated static func preview(_ data: Data, limit: Int = 240) -> String {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? "<\(data.count) non-text bytes>"
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }
    
    nonisolated static func describe(_ error: Error) -> String {
        if let xtream = error as? XtreamError {
            return xtream.errorDescription ?? String(describing: xtream)
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost:
                return "Could not resolve host (DNS). Check the server address."
            case .cannotConnectToHost:
                return "Could not connect to the host. Check the address and port."
            case .timedOut:
                return "Connection timed out."
            case .notConnectedToInternet:
                return "No internet connection."
            case .networkConnectionLost:
                return "Network connection was lost."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
                return "TLS/SSL failed. Try http vs https, or the certificate is untrusted."
            case .appTransportSecurityRequiresSecureConnection:
                return "App Transport Security blocked this HTTP URL. Use https, or the app must allow insecure HTTP."
            case .badURL, .unsupportedURL:
                return "Invalid URL: \(urlError.localizedDescription)"
            case .cannotDecodeContentData, .cannotParseResponse:
                return "Could not decode the server response."
            default:
                return urlError.localizedDescription
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

struct ListDiagnosis: Equatable {
    var title: String
    var detail: String
    var isEmpty: Bool
    var isError: Bool
    var isLoading: Bool
}
