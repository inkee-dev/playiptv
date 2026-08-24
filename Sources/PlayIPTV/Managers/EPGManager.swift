import Foundation
import Combine

/// Manager for EPG (Electronic Program Guide) data
/// Supports multiple EPG sources with per-source and global fallback
@MainActor
class EPGManager: ObservableObject {
    static let shared = EPGManager()
    
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var lastUpdateTime: Date?
    
    // Track loading state per source
    @Published var loadingSourceIds: Set<UUID> = []
    @Published var sourceUpdateTimes: [UUID: Date] = [:]
    @Published var sourceErrors: [UUID: String] = [:]
    
    // Store EPG data per source ID + global
    private var sourceEPGData: [UUID: [EPGChannel]] = [:] // sourceId -> channels
    private var globalEPGData: [EPGChannel] = []
    
    // Lookup tables per source
    private var sourceLookup: [UUID: [String: EPGChannel]] = [:]
    private var globalLookup: [String: EPGChannel] = [:]
    
    private init() {}
    
    /// Load EPG data for a specific source
    func loadEPG(for sourceId: UUID, from urlString: String) async {
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                lastError = "Invalid EPG URL for source"
            }
            return
        }
        
        await MainActor.run {
            loadingSourceIds.insert(sourceId)
            sourceErrors.removeValue(forKey: sourceId)
        }
        
        do {
            DebugLog.shared.info("Loading EPG from \(DebugLog.redact(urlString))", category: "EPG")
            let (data, _) = try await URLSession.shared.data(from: url)
            
            guard let xmlContent = String(data: data, encoding: .utf8) else {
                throw EPGError.invalidData
            }
            
            print("DEBUG: EPG → Parsing XML data (\(data.count) bytes)")
            let channels = try await XMLTVParser.parse(xmlContent: xmlContent)
            
            await MainActor.run {
                self.sourceEPGData[sourceId] = channels
                self.buildSourceLookup(for: sourceId, channels: channels)
                self.loadingSourceIds.remove(sourceId)
                self.sourceUpdateTimes[sourceId] = Date()
                self.sourceErrors.removeValue(forKey: sourceId)
                DebugLog.shared.success("Loaded \(channels.count) EPG channels", category: "EPG")
            }
            
        } catch {
            await MainActor.run {
                self.loadingSourceIds.remove(sourceId)
                self.sourceErrors[sourceId] = error.localizedDescription
                DebugLog.shared.error("EPG load failed: \(DebugLog.describe(error))", category: "EPG")
            }
        }
    }
    
    /// Load global EPG data (fallback)
    func loadGlobalEPG(from urlString: String) async {
        guard let url = URL(string: urlString) else {
            await MainActor.run {
                lastError = "Invalid global EPG URL"
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
            lastError = nil
        }
        
        do {
            DebugLog.shared.info("Loading global EPG from \(DebugLog.redact(urlString))", category: "EPG")
            let (data, _) = try await URLSession.shared.data(from: url)
            
            guard let xmlContent = String(data: data, encoding: .utf8) else {
                throw EPGError.invalidData
            }
            
            print("DEBUG: EPG → Parsing global XML data (\(data.count) bytes)")
            let channels = try await XMLTVParser.parse(xmlContent: xmlContent)
            
            await MainActor.run {
                self.globalEPGData = channels
                self.buildGlobalLookup(channels: channels)
                self.isLoading = false
                self.lastUpdateTime = Date()
                self.lastError = nil
                DebugLog.shared.success("Loaded \(channels.count) channels for global EPG", category: "EPG")
            }
            
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.lastError = error.localizedDescription
                DebugLog.shared.error("Global EPG load failed: \(DebugLog.describe(error))", category: "EPG")
            }
        }
    }
    
    /// Get current program for a channel by name and source
    /// Falls back to global EPG if source-specific EPG not available
    func getCurrentProgram(for channelName: String, sourceId: UUID?) -> EPGProgram? {
        let normalized = normalizeChannelName(channelName)
        
        // Try source-specific EPG first
        if let sourceId = sourceId,
           let sourceLookup = sourceLookup[sourceId],
           let program = sourceLookup[normalized]?.getCurrentProgram() {
            return program
        }
        
        // Fall back to global EPG
        return globalLookup[normalized]?.getCurrentProgram()
    }
    
    /// Get next program for a channel by name and source
    func getNextProgram(for channelName: String, sourceId: UUID?) -> EPGProgram? {
        let normalized = normalizeChannelName(channelName)
        
        // Try source-specific EPG first
        if let sourceId = sourceId,
           let sourceLookup = sourceLookup[sourceId],
           let program = sourceLookup[normalized]?.getNextProgram() {
            return program
        }
        
        // Fall back to global EPG
        return globalLookup[normalized]?.getNextProgram()
    }
    
    /// Clear all EPG data
    func clearEPG() {
        sourceEPGData = [:]
        globalEPGData = []
        sourceLookup = [:]
        globalLookup = [:]
        lastUpdateTime = nil
        lastError = nil
    }
    
    /// Clear EPG data for a specific source
    func clearEPG(for sourceId: UUID) {
        sourceEPGData.removeValue(forKey: sourceId)
        sourceLookup.removeValue(forKey: sourceId)
    }
    
    // MARK: - Private Helpers
    
    private func buildSourceLookup(for sourceId: UUID, channels: [EPGChannel]) {
        var lookup: [String: EPGChannel] = [:]
        
        for channel in channels {
            let normalized = normalizeChannelName(channel.displayName)
            lookup[normalized] = channel
        }
        
        sourceLookup[sourceId] = lookup
        print("DEBUG: EPG → Built lookup table for source \(sourceId) with \(lookup.count) entries")
    }
    
    private func buildGlobalLookup(channels: [EPGChannel]) {
        globalLookup.removeAll()
        
        for channel in channels {
            let normalized = normalizeChannelName(channel.displayName)
            globalLookup[normalized] = channel
        }
        
        print("DEBUG: EPG → Built global lookup table with \(globalLookup.count) entries")
    }
    
    /// Normalize channel name for matching (lowercase, trim, remove special chars)
    private func normalizeChannelName(_ name: String) -> String {
        return name
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }
}
