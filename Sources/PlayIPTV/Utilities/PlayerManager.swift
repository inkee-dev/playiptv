import Foundation
import VLCKit

@MainActor
class PlayerManager: NSObject, ObservableObject {
    static let shared = PlayerManager()
    
    @Published private(set) var player = VLCMediaPlayer()
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var hasError: Bool = false
    
    private var currentUrl: URL?
    private var currentStreamId: String?
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
    
    func play(url: URL, streamId: String? = nil, startPosition: Double? = nil, force: Bool = false) {
        if !force && currentUrl == url && player.isPlaying {
            print("DEBUG: VLC → Already playing \(url.lastPathComponent)")
            return
        }
        
        print("DEBUG: VLC → Loading \(url.lastPathComponent)")
        currentUrl = url
        currentStreamId = streamId
        
        // Explicitly start loading
        isLoading = true
        hasError = false
        
        // Cancel any existing timeout
        timeoutTask?.cancel()
        
        // Set a timeout for loading (10 seconds)
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            if !Task.isCancelled && isLoading {
                print("DEBUG: VLC → Timeout - Stream failed to load within 10 seconds")
                isLoading = false
                hasError = true
            }
        }
        
        let media = VLCMedia(url: url)
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
        
        player.stop()
        player.media = nil
        currentUrl = nil
        currentStreamId = nil
        isPlaying = false
        isLoading = false
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
                
                if !isLoading {
                    isLoading = true
                    hasError = false // Clear any previous errors
                    print("DEBUG: Loading started")
                }
                
            case .error:
                // Stream encountered an error
                timeoutTask?.cancel() // Cancel timeout
                isLoading = false
                hasError = true
                print("DEBUG: VLC Error - Stream failed to load")
                
            case .stopped:
                // If we were loading and now stopped, it's an error
                timeoutTask?.cancel() // Cancel timeout
                if isLoading {
                    isLoading = false
                    hasError = true
                    print("DEBUG: VLC Stopped - Stream failed to load (went from buffering to stopped)")
                }
                
            case .playing:
                // Successfully playing
                timeoutTask?.cancel() // Cancel timeout
                isLoading = false
                hasError = false
                
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
