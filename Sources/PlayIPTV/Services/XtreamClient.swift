import Foundation

enum XtreamError: Error, LocalizedError {
    case invalidURL
    case authenticationFailed
    case networkError
    case decodingError
    case httpStatus(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Xtream server URL"
        case .authenticationFailed:
            return "Authentication failed. Check username and password."
        case .networkError:
            return "Network error talking to the Xtream server"
        case .decodingError:
            return "Server response was not valid Xtream JSON"
        case .httpStatus(let code, let action):
            return "HTTP \(code) from \(action)"
        }
    }
}

struct XtreamClient {
    let baseURL: URL
    let serverURL: URL // Base server URL without player_api.php
    let username: String
    let password: String
    let sourceName: String
    
    init?(url: String, username: String, password: String, sourceName: String = "Xtream") {
        guard let validURL = URL(string: url) else { return nil }
        self.baseURL = validURL
        
        // Extract server URL (remove player_api.php if present)
        var serverURLString = url
        if serverURLString.hasSuffix("/player_api.php") {
            serverURLString = String(serverURLString.dropLast("/player_api.php".count))
        } else if serverURLString.hasSuffix("player_api.php") {
            serverURLString = String(serverURLString.dropLast("player_api.php".count))
        }
        
        guard let validServerURL = URL(string: serverURLString) else { return nil }
        self.serverURL = validServerURL
        
        self.username = username
        self.password = password
        self.sourceName = sourceName
    }
    
    private func request(action: String, extraQuery: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("player_api.php"), resolvingAgainstBaseURL: true)
        var queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "action", value: action)
        ]
        queryItems.append(contentsOf: extraQuery)
        components?.queryItems = queryItems
        guard let url = components?.url else { throw XtreamError.invalidURL }
        
        DebugLog.log(.info, "GET \(DebugLog.redact(url))", source: sourceName, category: "Xtream")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode
            DebugLog.log(
                .info,
                "HTTP \(status.map(String.init) ?? "n/a") · \(data.count) bytes for \(action)",
                source: sourceName,
                category: "Xtream"
            )
            
            if let status, !(200...299).contains(status) {
                DebugLog.log(.error, "Request failed for \(action)", source: sourceName, category: "Xtream", detail: DebugLog.preview(data))
                throw XtreamError.httpStatus(status, action)
            }
            return data
        } catch let error as XtreamError {
            throw error
        } catch {
            DebugLog.log(.error, DebugLog.describe(error), source: sourceName, category: "Xtream")
            throw error
        }
    }
    
    private func decodeArray<T: Decodable>(_ type: T.Type, from data: Data, action: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            DebugLog.log(
                .error,
                "Could not parse \(action) JSON",
                source: sourceName,
                category: "Xtream",
                detail: DebugLog.preview(data)
            )
            throw XtreamError.decodingError
        }
    }
    
    // Just verifying login
    func authenticate() async throws -> Bool {
        let data = try await request(action: "get_live_categories")
        
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let userInfo = object["user_info"] as? [String: Any] {
            let auth = userInfo["auth"]
            let denied = (auth as? Int == 0) || (auth as? String == "0")
            if denied {
                DebugLog.log(.error, "Server rejected credentials (auth=0)", source: sourceName, category: "Xtream")
                throw XtreamError.authenticationFailed
            }
        }
        
        return true
    }
    
    func fetchLiveStreams(categoryId: String?) async throws -> [Channel] {
        var extra: [URLQueryItem] = []
        if let catId = categoryId {
            extra.append(URLQueryItem(name: "category_id", value: catId))
        }
        let data = try await request(action: "get_live_streams", extraQuery: extra)
        
        struct XtreamStreamDTO: Decodable {
            let stream_id: Int
            let name: String
            let stream_icon: String?
            let category_id: String?
        }
        
        let streams = try decodeArray([XtreamStreamDTO].self, from: data, action: "get_live_streams")
        DebugLog.log(.info, "Parsed \(streams.count) live streams", source: sourceName, category: "Xtream")
        
        return streams.map { dto in
            // Xtream live stream URL format: http://domain:port/live/username/password/stream_id.ts
            var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: true)
            components?.path = "/live/\(username)/\(password)/\(dto.stream_id).ts"
            
            let streamUrl = components?.url ?? serverURL
            
            return Channel(
                streamId: String(dto.stream_id),
                name: dto.name,
                logoUrl: dto.stream_icon != nil ? URL(string: dto.stream_icon!) : nil,
                streamUrl: streamUrl,
                categoryId: dto.category_id ?? "0",
                groupTitle: nil,
                isSeries: false
            )
        }
    }
    
    // Fetches Movies (VOD)
    func fetchVODStreams(categoryId: String?) async throws -> [Channel] {
        var extra: [URLQueryItem] = []
        if let catId = categoryId {
            extra.append(URLQueryItem(name: "category_id", value: catId))
        }
        let data = try await request(action: "get_vod_streams", extraQuery: extra)
        
        struct XtreamVODDTO: Decodable {
            let stream_id: Int
            let name: String
            let stream_icon: String?
            let category_id: String?
            let container_extension: String?
        }
        
        let vods = try decodeArray([XtreamVODDTO].self, from: data, action: "get_vod_streams")
        DebugLog.log(.info, "Parsed \(vods.count) VOD streams", source: sourceName, category: "Xtream")
        
        return vods.map { dto in
            let ext = dto.container_extension ?? "mp4"
            
            var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: true)
            components?.path = "/movie/\(username)/\(password)/\(dto.stream_id).\(ext)"
            
            let streamUrl = components?.url ?? serverURL
            
            return Channel(
                streamId: String(dto.stream_id),
                name: dto.name,
                logoUrl: dto.stream_icon != nil ? URL(string: dto.stream_icon!) : nil,
                streamUrl: streamUrl,
                categoryId: dto.category_id ?? "0",
                groupTitle: nil,
                isSeries: false
            )
        }
    }
    
    // Fetches Series
    func fetchSeries(categoryId: String?) async throws -> [Channel] {
        var extra: [URLQueryItem] = []
        if let catId = categoryId {
            extra.append(URLQueryItem(name: "category_id", value: catId))
        }
        let data = try await request(action: "get_series", extraQuery: extra)
        
        struct XtreamSeriesDTO: Decodable {
            let series_id: Int
            let name: String
            let cover: String?
            let category_id: String?
        }
        
        let series = try decodeArray([XtreamSeriesDTO].self, from: data, action: "get_series")
        DebugLog.log(.info, "Parsed \(series.count) series", source: sourceName, category: "Xtream")
        
        return series.map { dto in
            // Series don't have a single stream URL usually, they have episodes.
            // But for the channel list, we track them here.
            // We might need a separate call to get episodes for a series.
            // For now, we'll placeholder the URL or use a special scheme to indicate it's a series to open.
            let seriesUrl = URL(string: "series://\(dto.series_id)")!
            
            return Channel(
                streamId: String(dto.series_id),
                name: dto.name,
                logoUrl: dto.cover != nil ? URL(string: dto.cover!) : nil,
                streamUrl: seriesUrl,
                categoryId: dto.category_id ?? "0",
                groupTitle: nil,
                isSeries: true
            )
        }
    }
    
    // Fetch episodes for a specific series
    func fetchSeriesInfo(seriesId: String) async throws -> SeriesInfo {
        let data = try await request(
            action: "get_series_info",
            extraQuery: [URLQueryItem(name: "series_id", value: seriesId)]
        )
        
        struct SeriesInfoDTO: Decodable {
            let episodes: [String: [EpisodeDTO]]
        }
        
        struct EpisodeDTO: Decodable {
            let id: String
            let episode_num: Int
            let season: Int
            let title: String?
            let container_extension: String
        }
        
        let info = try decodeArray(SeriesInfoDTO.self, from: data, action: "get_series_info")
        
        var allEpisodes: [Episode] = []
        for (_, seasonEpisodes) in info.episodes {
            for ep in seasonEpisodes {
                var components = URLComponents(url: serverURL, resolvingAgainstBaseURL: true)
                components?.path = "/series/\(username)/\(password)/\(ep.id).\(ep.container_extension)"
                
                let episodeUrl = components?.url ?? serverURL
                
                allEpisodes.append(Episode(
                    id: ep.id,
                    episodeNum: ep.episode_num,
                    seasonNum: ep.season,
                    title: ep.title,
                    streamUrl: episodeUrl,
                    containerExtension: ep.container_extension
                ))
            }
        }
        
        return SeriesInfo(seriesId: seriesId, episodes: allEpisodes.sorted { ($0.seasonNum, $0.episodeNum) < ($1.seasonNum, $1.episodeNum) })
    }
}
