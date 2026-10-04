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
}
