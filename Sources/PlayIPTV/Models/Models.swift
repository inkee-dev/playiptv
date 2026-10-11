import Foundation

enum StreamType: String, Codable {
    case m3u
    case xtream
    case stalker

    var displayName: String {
        switch self {
        case .m3u: return "M3U Playlist"
        case .xtream: return "Xtream Codes"
        case .stalker: return "Stalker Portal"
        }
    }
}

enum CategoryType: String, CaseIterable, Identifiable {
    case live
    case movie
    case series
    
    var id: String { rawValue }
}

struct Category: Identifiable, Hashable {
    let id: String
    let name: String
    let type: CategoryType
}

struct Channel: Identifiable, Hashable {
    let id: UUID = UUID() // Unique ID for UI stability
    var sourceId: UUID = UUID() // Link to origin source
    let streamId: String // The actual ID from source (URL or API ID)
    let name: String
    let logoUrl: URL?
    let streamUrl: URL
    let categoryId: String
    let groupTitle: String? // Raw group title from M3U
    let isSeries: Bool // Flag to indicate if this is a series container requiring episode selection
    
    var isVODPlayback: Bool {
        if isSeries { return false }
        
        let lowerGroup = groupTitle?.lowercased() ?? ""
        let lowerCat = categoryId.lowercased()
        
        // Movie markers
        if lowerCat.contains("movie") || lowerGroup.contains("movie") { return true }
        
        // Series Episode markers (when not the container)
        if lowerCat.contains("series") || lowerGroup.contains("series") { return true }
        
        // Exclude live
        if lowerCat.contains("live") || lowerGroup.contains("live") { return false }
        
        return false
    }
}

struct Episode: Identifiable, Hashable {
    let id: String
    let episodeNum: Int
    let seasonNum: Int
    let title: String?
    let streamUrl: URL
    let containerExtension: String
}

struct SeriesInfo {
    let seriesId: String
    let episodes: [Episode]
}

enum SourceExpiration: Equatable, Sendable, Codable {
    case date(Date)
    case never

    var isExpired: Bool {
        if case .date(let date) = self { return date < Date() }
        return false
    }

    var isExpiringSoon: Bool {
        guard case .date(let date) = self else { return false }
        let remaining = date.timeIntervalSinceNow
        return remaining >= 0 && remaining < 7 * 24 * 60 * 60
    }

    var summary: String {
        switch self {
        case .never:
            return "No expiration"
        case .date(let date):
            let showTime = abs(date.timeIntervalSinceNow) < 2 * 24 * 60 * 60
            let formatted = showTime
                ? date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
                : date.formatted(.dateTime.day().month(.abbreviated).year())
            return date < Date() ? "Expired \(formatted)" : "Expires \(formatted)"
        }
    }

    var detail: String {
        switch self {
        case .never:
            return "This subscription does not expire."
        case .date(let date):
            let when = date.formatted(date: .complete, time: .shortened)
            let relative = date.formatted(.relative(presentation: .named))
            return date < Date() ? "Expired \(relative) · \(when)" : "Expires \(relative) · \(when)"
        }
    }

    func menuTitle(sourceName: String) -> String {
        "\(sourceName) — \(summary)"
    }

    static func fromXtreamUserInfo(_ userInfo: [String: Any]) -> SourceExpiration? {
        guard userInfo.keys.contains("exp_date") else { return nil }
        switch parseExpiryValue(userInfo["exp_date"]) {
        case .date(let date):
            return .date(date)
        case .never:
            return .never
        case .unrecognized:
            return nil
        }
    }

    static func fromStalkerProfile(_ profile: [String: Any]) -> SourceExpiration? {
        let keys = [
            "expire_billing_date",
            "tariff_expired_date",
            "end_date",
            "account_end_date",
            "expire_date",
            "exp_date"
        ]
        var sawOpenEnded = false
        for key in keys where profile.keys.contains(key) {
            switch parseExpiryValue(profile[key]) {
            case .date(let date):
                return .date(date)
            case .never:
                sawOpenEnded = true
            case .unrecognized:
                continue
            }
        }
        return sawOpenEnded ? .never : nil
    }

    private enum ParsedExpiry {
        case date(Date)
        case never
        case unrecognized
    }

    private static func parseExpiryValue(_ value: Any?) -> ParsedExpiry {
        if value == nil || value is NSNull { return .never }
        if value is Bool { return .unrecognized }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if trimmed.isEmpty || lower == "null" || lower == "none" || lower == "unlimited" || lower == "0" || lower.hasPrefix("0000-00-00") {
                return .never
            }
            if let date = parseDate(trimmed), isSubscriptionDate(date) {
                return .date(date)
            }
            return .unrecognized
        }
        if let number = value as? NSNumber {
            if number.doubleValue <= 0 { return .never }
            if let date = dateFromUnix(number.doubleValue), isSubscriptionDate(date) {
                return .date(date)
            }
            return .never
        }
        return .unrecognized
    }

    private static func parseDate(_ text: String) -> Date? {
        if let number = Double(text) {
            return dateFromUnix(number)
        }
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd",
            "dd-MM-yyyy HH:mm:ss",
            "dd-MM-yyyy",
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy",
            "dd.MM.yyyy HH:mm:ss",
            "dd.MM.yyyy"
        ]
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone.current
        for format in formats {
            parser.dateFormat = format
            if let date = parser.date(from: text) {
                return date
            }
        }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func dateFromUnix(_ number: Double) -> Date? {
        guard number > 0 else { return nil }
        let seconds = number > 10_000_000_000 ? number / 1000 : number
        return Date(timeIntervalSince1970: seconds)
    }

    /// Epoch and zero-dates are how portals say "not set", not a real subscription end.
    private static func isSubscriptionDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970 > 946_684_800
    }
}

struct Source: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var type: StreamType
    
    // M3U
    var m3uUrl: String?
    
    // Xtream
    var xtreamUrl: String?
    var xtreamUser: String?
    var xtreamPass: String?
    
    // EPG
    var epgUrl: String?
    var epgRefreshInterval: String? // Stores EPGRefreshInterval rawValue

    // Stalker / Ministra portal
    var stalkerUrl: String? = nil
    var stalkerMac: String? = nil
    var stalkerLogin: String? = nil
    var stalkerPassword: String? = nil
    
    var url: URL? {
        switch type {
        case .m3u:
            return m3uUrl.flatMap { URL(string: $0) }
        case .xtream:
            return xtreamUrl.flatMap { URL(string: $0) }
        case .stalker:
            return stalkerUrl.flatMap { URL(string: $0) }
        }
    }

    func menuTitle(expiration: SourceExpiration?) -> String {
        guard let expiration else { return name }
        return expiration.menuTitle(sourceName: name)
    }
}
