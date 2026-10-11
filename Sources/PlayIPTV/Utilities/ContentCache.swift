import Foundation

enum ContentCache {
    struct CatalogSnapshot: Codable {
        var fetchedAt: Date
        var channels: [Channel]
        var categories: [Category]
    }

    struct GuideSnapshot: Codable {
        var fetchedAt: Date
        var channels: [EPGChannel]
    }

    static func loadCatalogs(for ids: [UUID]) -> [UUID: CatalogSnapshot] {
        var loaded: [UUID: CatalogSnapshot] = [:]
        for id in ids {
            if let snapshot = read(CatalogSnapshot.self, from: catalogURL(id)) {
                loaded[id] = snapshot
            }
        }
        return loaded
    }

    static func loadGuides(for ids: [UUID]) -> [UUID: GuideSnapshot] {
        var loaded: [UUID: GuideSnapshot] = [:]
        for id in ids {
            if let snapshot = read(GuideSnapshot.self, from: guideURL(id)) {
                loaded[id] = snapshot
            }
        }
        return loaded
    }

    static func loadGlobalGuide() -> GuideSnapshot? {
        read(GuideSnapshot.self, from: globalGuideURL())
    }

    static func saveCatalog(_ snapshot: CatalogSnapshot, id: UUID) {
        write(snapshot, to: catalogURL(id))
    }

    static func saveGuide(_ channels: [EPGChannel], id: UUID, fetchedAt: Date) {
        write(GuideSnapshot(fetchedAt: fetchedAt, channels: channels), to: guideURL(id))
    }

    static func saveGlobalGuide(_ channels: [EPGChannel], fetchedAt: Date) {
        write(GuideSnapshot(fetchedAt: fetchedAt, channels: channels), to: globalGuideURL())
    }

    static func removeCatalog(_ id: UUID) {
        try? FileManager.default.removeItem(at: catalogURL(id))
    }

    static func removeGuide(_ id: UUID) {
        try? FileManager.default.removeItem(at: guideURL(id))
    }

    static func removeGlobalGuide() {
        try? FileManager.default.removeItem(at: globalGuideURL())
    }

    private static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("PlayIPTV/Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func catalogURL(_ id: UUID) -> URL {
        directory().appendingPathComponent("catalog-\(id.uuidString).json")
    }

    private static func guideURL(_ id: UUID) -> URL {
        directory().appendingPathComponent("guide-\(id.uuidString).json")
    }

    private static func globalGuideURL() -> URL {
        directory().appendingPathComponent("guide-global.json")
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
