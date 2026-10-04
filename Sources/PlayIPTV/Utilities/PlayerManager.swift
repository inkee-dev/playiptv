import Foundation
import VLCKit

@MainActor
class PlayerManager: NSObject, ObservableObject {
    static let shared = PlayerManager()
    
    @Published private(set) var player = VLCMediaPlayer()
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var hasError: Bool = false
    /// Redacted URL and connection context shown while a stream is opening.
    @Published var playbackDetail: String?
    /// Why playback failed, including the HTTP check when one was made.
    @Published var errorDetail: String?
    
    private var currentUrl: URL?
    private var currentStreamId: String?
    private var currentUserAgent: String?
    private var currentReferrer: String?
    private var channelName: String?
    private var sourceName: String?
    private var failureReason: String?
    private var probeSummary: String?
    private var probeTask: Task<Void, Never>?
    private var suppressStateFailure = false
    private var announcedPlayback = false
    private var positionSaveTimer: Timer?
    private var debounceTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var shouldDisableSubtitles: Bool = false
    
    override init() {
        super.init()
        player.delegate = self
        print("DEBUG: VLC → PlayerManager initialized")
    }
    
    // MARK: - Playback Control
    
    func play(
        url: URL,
        streamId: String? = nil,
        startPosition: Double? = nil,
        force: Bool = false,
        userAgent: String? = nil,
        referrer: String? = nil,
        channelName: String? = nil,
        sourceName: String? = nil
    ) {
        if !force && currentUrl == url && player.isPlaying {
            print("DEBUG: VLC → Already playing \(url.lastPathComponent)")
            return
        }
        
        print("DEBUG: VLC → Loading \(url.lastPathComponent)")
        currentUrl = url
        currentStreamId = streamId
        currentUserAgent = userAgent
        currentReferrer = referrer
        self.channelName = channelName
        self.sourceName = sourceName
        failureReason = nil
        probeSummary = nil
        announcedPlayback = false
        probeTask?.cancel()
        probeTask = nil
        
        // Explicitly start loading
        isLoading = true
        hasError = false
        errorDetail = nil
        playbackDetail = contextLines().joined(separator: "\n")
        DebugLog.shared.info(
            "Opening \(channelName ?? url.lastPathComponent)",
            source: sourceName,
            category: "Playback",
            detail: playbackDetail
        )
        
        // Cancel any existing timeout
        timeoutTask?.cancel()
        
        // Set a timeout for loading (10 seconds)
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            if !Task.isCancelled && isLoading {
                let state = vlcStateName(player.state)
                noteFailure("Timed out after 10 seconds. The player was still \(state).")
            }
        }
        
        let media = VLCMedia(url: url)
        if let userAgent, !userAgent.isEmpty {
            media.addOption(":http-user-agent=\(userAgent)")
        }
        if let referrer, !referrer.isEmpty {
            media.addOption(":http-referrer=\(referrer)")
        }
        for option in ProxySettings.shared.vlcMediaOptions() {
            media.addOption(option)
        }
        
        // Use Task to prevent blocking UI during VLC network operations
        // VLC operations must stay on MainActor but Task makes them async
        Task.detached { @MainActor [weak self] in
            guard let self = self else { return }
            
            self.player.media = media
            
            // Flag to disable subtitles when they become available
            self.shouldDisableSubtitles = true
            
            self.player.play()
            
            // Log initial subtitle state
            print("DEBUG: Subtitle → Initial state after play(): \(self.player.currentVideoSubTitleIndex)")
            
            // Disable subtitles by default - try multiple times to ensure it sticks
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            guard !Task.isCancelled else { return }
            
            print("DEBUG: Subtitle → State at 0.3s: \(self.player.currentVideoSubTitleIndex)")
            print("DEBUG: Subtitle → Available tracks: \(String(describing: self.player.videoSubTitlesNames))")
            print("DEBUG: Subtitle → Available indexes: \(String(describing: self.player.videoSubTitlesIndexes))")
            if self.shouldDisableSubtitles {
                self.player.currentVideoSubTitleIndex = -1
                print("DEBUG: Subtitle → Set to -1 at 0.3s, current: \(self.player.currentVideoSubTitleIndex)")
            }
            
            try? await Task.sleep(nanoseconds: 400_000_000) // Additional 0.4s (total 0.7s)
            guard !Task.isCancelled else { return }
            
            print("DEBUG: Subtitle → State at 0.7s: \(self.player.currentVideoSubTitleIndex)")
            if self.shouldDisableSubtitles {
                self.player.currentVideoSubTitleIndex = -1
                print("DEBUG: Subtitle → Set to -1 at 0.7s, current: \(self.player.currentVideoSubTitleIndex)")
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            print("DEBUG: Subtitle → State at 1.5s: \(self.player.currentVideoSubTitleIndex)")
            if self.shouldDisableSubtitles {
                self.player.currentVideoSubTitleIndex = -1
                print("DEBUG: Subtitle → Set to -1 at 1.5s, current: \(self.player.currentVideoSubTitleIndex)")
            }
        }
        
        // Seek to saved position if provided
        if let position = startPosition {
            // Wait a bit for media to load before seeking
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.player.time = VLCTime(int: Int32(position * 1000))
            }
        }
        
        // Start periodic position saving for VOD
        startPositionTracking()
    }
    
    func stop() {
        print("DEBUG: VLC → Stopping playback")
        shouldDisableSubtitles = false
        saveCurrentPosition()
        stopPositionTracking()
        
        debounceTask?.cancel()
        debounceTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        probeTask?.cancel()
        probeTask = nil
        
        player.stop()
        player.media = nil
        currentUrl = nil
        currentStreamId = nil
        currentUserAgent = nil
        currentReferrer = nil
        channelName = nil
        sourceName = nil
        failureReason = nil
        probeSummary = nil
        announcedPlayback = false
        isPlaying = false
        isLoading = false
        hasError = false
        playbackDetail = nil
        errorDetail = nil
    }

    /// Failure before the player starts, such as a link that could not be resolved.
    func presentFailure(_ detail: String) {
        timeoutTask?.cancel()
        probeTask?.cancel()
        probeTask = nil
        isLoading = false
        hasError = true
        playbackDetail = nil
        failureReason = detail
        errorDetail = detail
    }
    
    private func startPositionTracking() {
        stopPositionTracking()
        
        // Save position every 10 seconds
        positionSaveTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.saveCurrentPosition()
            }
        }
    }
    
    private func stopPositionTracking() {
        positionSaveTimer?.invalidate()
        positionSaveTimer = nil
    }
    
    private func saveCurrentPosition() {
        guard let streamId = currentStreamId,
              player.isSeekable else { return }
        
        let position = Double(player.time.intValue) / 1000.0 // Convert to seconds
        let duration = Double(player.media?.length.intValue ?? 0) / 1000.0
        PlaybackPositionManager.shared.savePosition(streamId: streamId, position: position, duration: duration)
    }
    
    private func noteFailure(_ reason: String) {
        guard !suppressStateFailure else { return }
        let reasonChanged = failureReason != reason
        if hasError && !reasonChanged { return }
        
        timeoutTask?.cancel()
        isLoading = false
        hasError = true
        playbackDetail = nil
        failureReason = reason
        startFailureProbeIfNeeded()
        errorDetail = composedDetail(reason: reason)
        if reasonChanged {
            print("DEBUG: VLC → \(reason)")
            DebugLog.shared.error(reason, source: sourceName, category: "Playback", detail: errorDetail)
        }
    }
    
    /// Probe only after playback has failed so a one-connection provider is not opened twice at once.
    private func startFailureProbeIfNeeded() {
        guard probeTask == nil, let url = currentUrl else { return }
        if url.isFileURL {
            probeSummary = FileManager.default.fileExists(atPath: url.path)
                ? "Local file exists: \(url.path)"
                : "Local file is missing: \(url.path)"
            return
        }
        
        let userAgent = currentUserAgent
        let referrer = currentReferrer
        probeTask = Task { @MainActor in
            self.suppressStateFailure = true
            self.player.stop()
            await Task.yield()
            self.suppressStateFailure = false
            guard !Task.isCancelled, self.currentUrl == url, self.hasError else { return }
            
            let report = await StreamProbe.inspect(url: url, userAgent: userAgent, referrer: referrer)
            guard !Task.isCancelled, self.currentUrl == url, self.hasError else { return }
            guard report.summary != "Stream check cancelled" else { return }
            
            self.probeSummary = report.summary
            let reason = self.failureReason ?? "Playback failed"
            self.errorDetail = self.composedDetail(reason: reason)
            DebugLog.shared.error(
                "Stream check for \(self.channelName ?? url.lastPathComponent)",
                source: self.sourceName,
                category: "Playback",
                detail: report.summary
            )
        }
    }
    
    private func composedDetail(reason: String) -> String {
        var lines = [reason]
        lines.append(contentsOf: contextLines())
        if let probeSummary {
            lines.append(probeSummary)
        } else if probeTask != nil {
            lines.append("Stream check: contacting the server…")
        }
        return lines.joined(separator: "\n")
    }
    
    private func contextLines() -> [String] {
        var lines: [String] = []
        if let channelName, !channelName.isEmpty {
            lines.append("Channel: \(channelName)")
        }
        if let sourceName, !sourceName.isEmpty {
            lines.append("Source: \(sourceName)")
        }
        if let currentUrl {
            lines.append("URL: \(DebugLog.redact(currentUrl))")
        }
        if let currentUserAgent, !currentUserAgent.isEmpty {
            lines.append("User-Agent: \(currentUserAgent)")
        }
        if let currentReferrer, !currentReferrer.isEmpty {
            lines.append("Referrer: \(DebugLog.redact(currentReferrer))")
        }
        lines.append(ProxySettings.shared.summaryForDebug())
        return lines
    }
    
    private func vlcStateName(_ state: VLCMediaPlayerState) -> String {
        switch state {
        case .stopped: return "stopped"
        case .opening: return "opening"
        case .buffering: return "buffering"
        case .ended: return "ended"
        case .error: return "error"
        case .playing: return "playing"
        case .paused: return "paused"
        default: return "state \(state.rawValue)"
        }
    }
    
    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
        } else {
            player.play()
        }
    }
    
    func setVolume(_ volume: Int32) {
        player.audio?.volume = volume
    }
    
    private var volumeBeforeMute: Int32 = 100
    
    func toggleMute() {
        if let currentVolume = player.audio?.volume {
            if currentVolume == 0 {
                // Unmute - restore previous volume
                player.audio?.volume = volumeBeforeMute
            } else {
                // Mute - save current volume and set to 0
                volumeBeforeMute = currentVolume
                player.audio?.volume = 0
            }
        }
    }
    
    func skip(seconds: Int) {
        guard player.isSeekable else { return }
        let currentTime = Int(player.time.intValue)
        let newTime = VLCTime(int: Int32(currentTime + (seconds * 1000))) // milliseconds
        player.time = newTime
    }
    
    func restart() {
        guard player.isSeekable else { return }
        player.time = VLCTime(int: 0)
        player.play()
    }
    
    func seek(to seconds: Double) {
        guard player.isSeekable else { return }
        player.time = VLCTime(int: Int32(seconds * 1000)) // Convert to milliseconds
    }
    
    func selectAudioTrack(index: Int) {
        // VLC uses indexes from audioTrackIndexes array
        if let indexes = player.audioTrackIndexes as? [Int32],
           index >= 0 && index < indexes.count {
            let vlcIndex = indexes[index]
            player.currentAudioTrackIndex = vlcIndex
            print("DEBUG: Audio - Array index: \(index), VLC index: \(vlcIndex), Current: \(player.currentAudioTrackIndex)")
            print("DEBUG: Audio - All VLC indexes: \(indexes)")
        }
    }
    
    func selectSubtitleTrack(index: Int) {
        if index == -1 {
            // Disable subtitles
            player.currentVideoSubTitleIndex = -1
            print("DEBUG: Subtitle - Disabled (set to -1)")
        } else if let indexes = player.videoSubTitlesIndexes as? [Int32],
                  index >= 0 && index < indexes.count {
            let vlcIndex = indexes[index]
            player.currentVideoSubTitleIndex = vlcIndex
            print("DEBUG: Subtitle - Array index: \(index), VLC index: \(vlcIndex), Current: \(player.currentVideoSubTitleIndex)")
            print("DEBUG: Subtitle - All VLC indexes: \(indexes)")
        }
    }
}

// MARK: - VLCMediaPlayerDelegate
extension PlayerManager: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        Task { @MainActor in
            isPlaying = player.isPlaying
            
            // Check loading state
            print("DEBUG: VLC State Changed: \(player.state.rawValue)")
            
            // Disable subtitles when tracks become available (regardless of state)
            if shouldDisableSubtitles {
                if let subtitleTracks = player.videoSubTitlesNames as? [String], !subtitleTracks.isEmpty {
                    print("DEBUG: Subtitle → Tracks now available in state \(player.state.rawValue): \(subtitleTracks)")
                    print("DEBUG: Subtitle → Current index before disable: \(player.currentVideoSubTitleIndex)")
                    player.currentVideoSubTitleIndex = -1
                    print("DEBUG: Subtitle → Disabled on state change, current: \(player.currentVideoSubTitleIndex)")
                    shouldDisableSubtitles = false // Only do this once per playback
                }
            }
            
            switch player.state {
            case .opening, .buffering:
                // Cancel pending stop
                debounceTask?.cancel()
                debounceTask = nil
                
                // Keep the failure details on screen while the follow-up stream check runs.
                if hasError {
                    break
                }
                
                if !isLoading {
                    isLoading = true
                    hasError = false
                    errorDetail = nil
                    print("DEBUG: Loading started")
                }
                
            case .error:
                timeoutTask?.cancel()
                noteFailure("Player reported an error (VLC state: error).")
                
            case .stopped:
                timeoutTask?.cancel()
                if isLoading {
                    noteFailure("Player stopped before the stream started (VLC state: stopped).")
                }
                
            case .playing:
                // Successfully playing
                timeoutTask?.cancel()
                probeTask?.cancel()
                probeTask = nil
                isLoading = false
                hasError = false
                playbackDetail = nil
                errorDetail = nil
                if !announcedPlayback {
                    announcedPlayback = true
                    DebugLog.shared.success(
                        "Playing \(channelName ?? currentUrl?.lastPathComponent ?? "stream")",
                        source: sourceName,
                        category: "Playback"
                    )
                }
                
            default:
                // Debounce stop (wait 0.5s) to prevent flickering on retry loops
                debounceTask?.cancel() 
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !Task.isCancelled {
                        isLoading = false
                        print("DEBUG: Loading ended (State: \(player.state.rawValue))")
                    }
                }
            }
        }
    }
    
    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        Task { @MainActor in
            // If time is advancing, we are definitely playing -> hide loading
            if isLoading {
                print("DEBUG: Time changed, forcing loading end")
                debounceTask?.cancel()  // Cancel pending debounced loading end
                isLoading = false
            }
        }
    }
}
