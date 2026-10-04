import SwiftUI
import VLCKit

/// Singleton container for VLC video view - ensures view is never recreated
@MainActor
class VLCViewContainer {
    static let shared = VLCViewContainer()
    
    let videoView: VLCVideoView
    
    private init() {
        videoView = VLCVideoView()
        videoView.autoresizingMask = [.width, .height]
        PlayerManager.shared.player.drawable = videoView
        print("DEBUG: VLC → Singleton video view created and drawable set")
    }
}

struct PlayerView: View {
    @Environment(AppState.self) private var appState
    @ObservedObject private var playerManager = PlayerManager.shared
    var isFullscreen: Bool = false
    
    var body: some View {
        if appState.playbackTarget.isExternal {
            ExternalStreamPlaceholder()
        } else {
            builtInPlayer
        }
    }

    private var builtInPlayer: some View {
        ZStack {
            SingletonVLCView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            
            // Loading Overlay
            if playerManager.isLoading {
                Color.black
                    .overlay {
                        VStack(spacing: 16) {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.large)
                                .environment(\.colorScheme, .dark) // Forces white spinner
                            if let detail = playerManager.playbackDetail, !detail.isEmpty {
                                Text(detail)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.75))
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: 560, alignment: .leading)
                            }
                        }
                        .padding(32)
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            // Error Overlay
            if playerManager.hasError {
                Color.black.opacity(0.9)
                    .overlay {
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.yellow)
                            
                            Text("Stream Unavailable")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            ScrollView {
                                Text(playerManager.errorDetail ?? "Unable to load the video stream.\nThe source may be offline or invalid.")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: 560, maxHeight: 220)
                            
                            HStack(spacing: 15) {
                                Button("Retry") {
                                    if let channel = appState.selectedChannel {
                                        appState.playChannel(channel, startPosition: nil, force: true)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button("Copy Details") {
                                    let text = playerManager.errorDetail ?? ""
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(text, forType: .string)
                                }
                                .buttonStyle(.bordered)
                                .disabled(playerManager.errorDetail == nil)
                                
                                Button("Close") {
                                    appState.selectedChannel = nil
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 10)
                        }
                        .padding(40)
                    }
                    .transition(.opacity)
                    .zIndex(2)
            }
            
            // Media controls overlay
            if appState.arePlayerControlsVisible, let channel = appState.selectedChannel {
                MediaControlsView(channel: channel, isFullscreen: isFullscreen)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                appState.arePlayerControlsVisible = hovering
            }
        }
        .onTapGesture {
            withAnimation {
                appState.arePlayerControlsVisible.toggle()
            }
        }
        .onChange(of: appState.playPauseSignal) { _, _ in
            PlayerManager.shared.togglePlayPause()
        }
    }
}

struct ExternalStreamPlaceholder: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 16) {
                if appState.isOpeningExternalStream {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    if let name = appState.selectedChannel?.name {
                        Text(name)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    Text("Opening in VLC")
                        .foregroundStyle(.white.opacity(0.75))
                } else if let error = appState.externalPlaybackError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.yellow)
                    Text("Could not open VLC")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text(error)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .frame(maxWidth: 560, alignment: .leading)
                    if let channel = appState.selectedChannel {
                        Button("Retry") {
                            appState.playChannel(channel, startPosition: nil, force: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 6)
                    }
                } else if let channel = appState.selectedChannel {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(channel.name)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Playing in VLC")
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SingletonVLCView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        print("DEBUG: VLC → Returning singleton video view")
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor
        
        let vlcView = VLCViewContainer.shared.videoView
        vlcView.frame = containerView.bounds
        vlcView.autoresizingMask = [.width, .height]
        containerView.addSubview(vlcView)
        
        // Also set background on the VLC view itself
        vlcView.wantsLayer = true
        vlcView.layer?.backgroundColor = NSColor.black.cgColor
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Ensure VLC view fills the container
        if let vlcView = nsView.subviews.first as? VLCVideoView {
            vlcView.frame = nsView.bounds
        }
    }
}

struct MediaControlsView: View {
    let channel: Channel
    let isFullscreen: Bool
    @ObservedObject private var playerManager = PlayerManager.shared
    @Environment(AppState.self) private var appState
    @State private var volume: Double = 100
    @State private var isScrubbing: Bool = false
    @State private var scrubbingPosition: Double = 0
    @State private var currentTimeDisplay: Double = 0
    @State private var pendingAudioIndex: Int32? = nil
    @State private var pendingSubtitleIndex: Int32? = nil
    @State private var volumeBeforeMute: Double = 100
    
    private var isLiveTV: Bool {
        // Live TV is anything that's not a series (movies and live TV don't have skip/restart)
        // Actually, movies should have controls, so check if it's truly live TV
        !channel.isSeries && (channel.categoryId.contains("Live") || channel.groupTitle?.contains("Live") == true)
    }
    
    private var currentTime: Double {
        isScrubbing ? scrubbingPosition : currentTimeDisplay
    }
    
    private var duration: Double {
        Double(playerManager.player.media?.length.intValue ?? 0) / 1000.0
    }
    
    private var isSeekable: Bool {
        playerManager.player.isSeekable
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func updateCurrentTime() {
        currentTimeDisplay = Double(playerManager.player.time.intValue) / 1000.0
    }
    
    private func getNextEpisode() -> Episode? {
        guard let currentEpisode = appState.currentEpisode else { return nil }
        
        let episodes = appState.episodesForSeries.sorted { ep1, ep2 in
            if ep1.seasonNum != ep2.seasonNum {
                return ep1.seasonNum < ep2.seasonNum
            }
            return ep1.episodeNum < ep2.episodeNum
        }
        
        guard let currentIndex = episodes.firstIndex(where: { $0.id == currentEpisode.id }),
              currentIndex + 1 < episodes.count else {
            return nil
        }
        
        return episodes[currentIndex + 1]
    }
    
    private func playNextEpisode(_ episode: Episode) {
        guard let seriesId = appState.currentSeriesId,
              let series = appState.channels.first(where: { $0.streamId == seriesId }) else {
            return
        }
        
        let episodeChannel = Channel(
            sourceId: series.sourceId,
            streamId: episode.id,
            name: episode.title ?? "Episode \(episode.episodeNum)",
            logoUrl: series.logoUrl,
            streamUrl: episode.streamUrl,
            categoryId: series.categoryId,
            groupTitle: series.groupTitle,
            isSeries: false
        )
        
        appState.selectedChannel = episodeChannel
        appState.playChannel(episodeChannel, startPosition: nil)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Timeline (VOD only) - above controls
            if !isLiveTV && isSeekable && duration > 0 {
                VStack(spacing: 8) {
                    // Timeline slider
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubbingPosition : currentTime },
                            set: { newValue in
                                isScrubbing = true
                                scrubbingPosition = newValue
                            }
                        ),
                        in: 0...duration,
                        onEditingChanged: { editing in
                            if !editing {
                                // Seek when user releases
                                playerManager.seek(to: scrubbingPosition)
                                isScrubbing = false
                            }
                        }
                    )
                    .tint(.white)
                    
                    // Time labels
                    HStack {
                        Text(formatTime(currentTime))
                            .font(.caption)
                            .foregroundColor(.white)
                        Spacer()
                        Text(formatTime(duration))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            
            HStack(spacing: 20) {
                // Media controls on the left
                HStack(spacing: 15) {
                    // VOD controls (movies/series only)
                    if !isLiveTV {
                        Button(action: {
                            playerManager.restart()
                        }) {
                            Image(systemName: "backward.end.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Restart from beginning")
                        
                        Button(action: {
                            playerManager.skip(seconds: -10)
                        }) {
                            Image(systemName: "gobackward.10")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Skip back 10 seconds")
                    }
                    
                    // Play/Pause (all types)
                    Button(action: {
                        playerManager.togglePlayPause()
                    }) {
                        Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .help(playerManager.isPlaying ? "Pause" : "Play")
                    
                    // VOD controls (movies/series only)
                    if !isLiveTV {
                        Button(action: {
                            playerManager.skip(seconds: 10)
                        }) {
                            Image(systemName: "goforward.10")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Skip forward 10 seconds")
                        
                        // Next episode button (series only)
                        if let nextEpisode = getNextEpisode() {
                            Button(action: {
                                playNextEpisode(nextEpisode)
                            }) {
                                Image(systemName: "forward.end.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .help("Next Episode")
                        }
                    }
                }
                
                Spacer()
                
                // Audio/Subtitle track selection
                HStack(spacing: 12) {
                    // Audio tracks - show if available
                    Menu {
                        if let audioTracks = playerManager.player.audioTrackNames as? [String],
                           let audioIndexes = playerManager.player.audioTrackIndexes as? [Int32] {
                            // Skip the first track only if it's "Disable" (VLC's built-in disable option at index 0)
                            let startIndex = (audioTracks.first?.lowercased() == "disable") ? 1 : 0
                            
                            ForEach(startIndex..<audioTracks.count, id: \.self) { index in
                                Button(action: {
                                    if index < audioIndexes.count {
                                        pendingAudioIndex = audioIndexes[index]
                                        playerManager.selectAudioTrack(index: index)
                                        // Clear pending after delay to allow VLC to catch up
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            pendingAudioIndex = nil
                                        }
                                    }
                                }) {
                                    HStack {
                                        Text(audioTracks[index])
                                        Spacer()
                                        // Compare against the actual VLC index or pending selection
                                        let vlcIndex = index < audioIndexes.count ? audioIndexes[index] : -999
                                        let isSelected = (pendingAudioIndex == vlcIndex) || (playerManager.player.currentAudioTrackIndex == vlcIndex)
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                        }
                                        let _ = print("DEBUG: Audio track[\(index)] '\(audioTracks[index])' - VLC idx: \(vlcIndex), Selected: \(isSelected)")
                                    }
                                }
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 44, height: 44)
                            Image(systemName: "waveform.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Audio Tracks")
                    
                    // Subtitle tracks - show if available
                    Menu {
                        Button(action: {
                            pendingSubtitleIndex = -1
                            playerManager.selectSubtitleTrack(index: -1)
                            // Clear pending after delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                pendingSubtitleIndex = nil
                            }
                        }) {
                            HStack {
                                Text("Off")
                                Spacer()
                                let isOff = (pendingSubtitleIndex == -1) || (playerManager.player.currentVideoSubTitleIndex == -1)
                                if isOff {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        if let subtitleTracks = playerManager.player.videoSubTitlesNames as? [String],
                           let subtitleIndexes = playerManager.player.videoSubTitlesIndexes as? [Int32] {
                            // Skip the first track only if it's "Disable" (VLC's built-in off option at index 0)
                            let startIndex = (subtitleTracks.first?.lowercased() == "disable") ? 1 : 0
                            
                            ForEach(startIndex..<subtitleTracks.count, id: \.self) { index in
                                Button(action: {
                                    if index < subtitleIndexes.count {
                                        pendingSubtitleIndex = subtitleIndexes[index]
                                        playerManager.selectSubtitleTrack(index: index)
                                        // Clear pending after delay
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            pendingSubtitleIndex = nil
                                        }
                                    }
                                }) {
                                    HStack {
                                        Text(subtitleTracks[index])
                                        Spacer()
                                        // Compare against the actual VLC index or pending selection
                                        let vlcIndex = index < subtitleIndexes.count ? subtitleIndexes[index] : -999
                                        let isSelected = (pendingSubtitleIndex == vlcIndex) || (playerManager.player.currentVideoSubTitleIndex == vlcIndex)
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.4))
                                .frame(width: 44, height: 44)
                            Image(systemName: "captions.bubble.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Subtitles")
                }
                
                // Volume control on the right
                HStack(spacing: 8) {
                    Button(action: {
                        if volume == 0 {
                            // Unmute - restore previous volume
                            volume = volumeBeforeMute
                            playerManager.setVolume(Int32(volumeBeforeMute))
                        } else {
                            // Mute - save current volume and set to 0
                            volumeBeforeMute = volume
                            volume = 0
                            playerManager.setVolume(0)
                        }
                    }) {
                        Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundColor(.white)
                            .frame(width: 20, alignment: .center)
                    }
                    .buttonStyle(.plain)
                    .help(volume == 0 ? "Unmute" : "Mute")
                    
                    Slider(value: $volume, in: 0...100)
                        .frame(width: 100)
                        .onChange(of: volume) { _, newValue in
                            playerManager.setVolume(Int32(newValue))
                            // Update volumeBeforeMute if user manually changes volume (not muting)
                            if newValue > 0 {
                                volumeBeforeMute = newValue
                            }
                        }
                }
                
                // Fullscreen toggle button
                Button(action: {
                    appState.fullscreenToggleSignal.toggle()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 44, height: 44)
                        Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .help(isFullscreen ? "Exit Fullscreen" : "Enter Fullscreen")
            }
            .padding(20)
            .contentShape(Rectangle())
            .onTapGesture {
                // Consume tap to prevent accidental control dismissal
                // When user clicks within the control bar area (between buttons),
                // it shouldn't hide the controls.
            }
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .onAppear {
            // Initialize current time immediately
            updateCurrentTime()
            
            // Update timeline every 0.5 seconds
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                if !isScrubbing {
                    updateCurrentTime()
                }
            }
            
            // Sync volume from VLC player periodically (for global mute shortcut)
            // Reduced from 0.1s to 1.0s to improve performance
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    if let vlcVolume = playerManager.player.audio?.volume {
                        volume = Double(vlcVolume)
                    }
                }
            }
        }
    }
}
