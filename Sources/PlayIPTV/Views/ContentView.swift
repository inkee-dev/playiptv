import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    
    @FocusState private var isPlayerFocused: Bool
    @State private var isWindowFullscreen: Bool = false  // Tracks macOS window fullscreen
    @State private var isVideoFullscreen: Bool = false   // Tracks immersive video fullscreen
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var detachedColumnVisibility = NavigationSplitViewVisibility.all
    @State private var isListView: Bool = true
    
    var body: some View {
        Group {
            if appState.sources.isEmpty {
                WelcomeView(appState: appState)
                    .frame(minWidth: 600, minHeight: 400)
            } else {
                mainContent
            }
        }
        .frame(minWidth: 915, minHeight: 300)  // 160 (sidebar) + 200 (grid) + 550 (player)
        .handleWindowFullscreen(isFullscreen: $isWindowFullscreen)
        .onChange(of: isWindowFullscreen) { _, newValue in
            // Sync video fullscreen state with window fullscreen state
            isVideoFullscreen = newValue
            
            // Hide channel browser when entering fullscreen
            if newValue {
                appState.isChannelBrowserVisible = false
            }
        }
        .onChange(of: appState.playPauseSignal) { _, _ in
            PlayerManager.shared.togglePlayPause()
        }
        .onChange(of: appState.fullscreenToggleSignal) { _, _ in
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
        .onChange(of: appState.muteToggleSignal) { _, _ in
            PlayerManager.shared.toggleMute()
        }
        .onKeyPress(.init("f")) {
            NSApp.keyWindow?.toggleFullScreen(nil)
            return .handled
        }
        .onKeyPress(.init("m")) {
            appState.muteToggleSignal.toggle()
            return .handled
        }
        .sheet(isPresented: $appState.showVODDialog) {
            if let channel = appState.vodDialogChannel {
                VODPlaybackDialog(
                    channel: channel,
                    savedPosition: appState.vodDialogSavedPosition,
                    onPlay: {
                        appState.playVODFromStart()
                    },
                    onResume: appState.vodDialogSavedPosition != nil ? {
                        appState.resumeVOD()
                    } : nil,
                    onCancel: {
                        appState.cancelVOD()
                    }
                )
            }
        }
        .sheet(isPresented: $appState.showUpdateDialog) {
            if let release = UpdateChecker.shared.latestRelease {
                UpdateNotificationView(
                    release: release,
                    onDownload: {
                        if let url = URL(string: release.htmlUrl) {
                            NSWorkspace.shared.open(url)
                        }
                        appState.showUpdateDialog = false
                    },
                    onSkip: {
                        UpdateChecker.shared.skipVersion(release.tagName)
                        appState.showUpdateDialog = false
                    },
                    onRemindLater: {
                        appState.showUpdateDialog = false
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if isVideoFullscreen, let channel = appState.selectedChannel {
            fullscreenPlayer(channel: channel)
        } else {
            attachedSplitView
        }
    }
    
    // Stable player view that persists across mode changes
    private var playerView: some View {
        PlayerView(isFullscreen: isVideoFullscreen)
            .id("stable-player-view") // Prevent recreation
            .focused($isPlayerFocused)
    }
    
    private var attachedSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(appState: appState)
                .frame(width: 160)
        } content: {
            ChannelGridView(
                appState: appState,
                isListView: $isListView
            )
        } detail: {
            ZStack {
                if let channel = appState.selectedChannel {
                    playerDetailView(channel: channel)
                } else {
                    ContentUnavailableView("Select a Channel", systemImage: "tv", description: Text("Choose a channel from the list to start watching."))
                }
            }
            .frame(minWidth: 550, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Spacer()
                    
                    sourcePickerMenu
                    
                    // View Mode
                    Picker("View Mode", selection: $isListView) {
                        Label("Grid", systemImage: "square.grid.2x2").tag(false)
                        Label("List", systemImage: "list.bullet").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    
                    // Debug
                    Button(action: {
                        openWindow(id: "debug")
                    }) {
                        Label("Debug", systemImage: "ant")
                    }
                    .help("Connection Debug")
                    
                    // Settings
                    Button(action: {
                        openSettings()
                    }) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .toolbarBackground(.visible, for: .windowToolbar)
            .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    private var detachedSplitView: some View {
        NavigationSplitView(columnVisibility: $detachedColumnVisibility) {
            SidebarView(appState: appState)
                .frame(width: 160)
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button(action: toggleSidebar) {
                            Image(systemName: "sidebar.left")
                        }
                        .help("Toggle Sidebar")
                    }
                }
        } detail: {
            ChannelGridView(
                appState: appState,
                isListView: $isListView
            )
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    private func fullscreenPlayer(channel: Channel) -> some View {
        // Determine if this is Live TV (not movies or series)
        let isLiveTV = !channel.isSeries && (channel.categoryId.lowercased().contains("live") || 
                                              channel.groupTitle?.lowercased().contains("live") == true)
        
        return ZStack(alignment: .topLeading) {
            // Main content
            HStack(spacing: 0) {
                // Channel Browser (Leading) - only for Live TV
                if isLiveTV && appState.isChannelBrowserVisible {
                    FullscreenChannelBrowserView(appState: appState)
                        .frame(width: 320)
                        .transition(.move(edge: .leading))
                }
                
                // Video Player
                playerView
                    .onAppear {
                        isPlayerFocused = true
                    }
            }
            
            // Toggle button - only for Live TV
            if isLiveTV && appState.arePlayerControlsVisible {
                Button(action: {
                    withAnimation {
                        appState.isChannelBrowserVisible.toggle()
                    }
                }) {
                    ZStack {
                        Circle()
                        .fill(.black.opacity(0.8))
                        .frame(width: 44, height: 44)
                        
                        Text(appState.isChannelBrowserVisible ? "◀" : "▶")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .help(appState.isChannelBrowserVisible ? "Hide Channels" : "Show Channels")
                .padding(.leading, appState.isChannelBrowserVisible ? 340 : 20)
                .padding(.top, 20)
                .transition(.opacity)
            }
        }
        .ignoresSafeArea(edges: [.bottom, .leading, .trailing])
    }
    
    private func playerDetailView(channel: Channel) -> some View {
        ZStack(alignment: .topTrailing) {
            playerView
                .onAppear {
                    isPlayerFocused = true
                }
            
            // Overlay buttons (hidden in video fullscreen)
            if !isVideoFullscreen {
                Button(action: {
                    appState.selectedChannel = nil
                    // Also explicitly stop the manager
                    PlayerManager.shared.stop()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.8))
                        .background(Circle().fill(Color.black.opacity(0.4)))
                }
                .buttonStyle(.plain)
                .help("Stop Playback")
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    private var sourcePickerMenu: some View {
        Menu {
            Picker("Source", selection: Binding(
                get: { appState.selectedSource },
                set: { appState.selectedSource = $0 }
            )) {
                ForEach(appState.sources) { source in
                    Text(source.name).tag(Optional(source))
                }
            }
            .pickerStyle(.inline)
            
            Divider()
            
            Button("Manage Sources...") {
                appState.settingsTab = .sources
                openSettings()
            }
        } label: {
            Text("\(appState.selectedSource?.name ?? "Select Source") ")
                .fontWeight(.medium)
            + Text(Image(systemName: "chevron.down"))
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(.secondary)
        }
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Custom Right-Aligned Toolbar
struct CustomToolbarView: View {
    var appState: AppState
    @Binding var isListView: Bool
    var onOpenSettings: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            
            // Source Picker
            Menu {
                Picker("Source", selection: Binding(
                    get: { appState.selectedSource },
                    set: { appState.selectedSource = $0 }
                )) {
                    ForEach(appState.sources) { source in
                        Text(source.name).tag(Optional(source))
                    }
                }
                .pickerStyle(.inline)
                
                Divider()
                
                Button("Manage Sources...") {
                    appState.settingsTab = .sources
                    onOpenSettings()
                }
            } label: {
                Label("Sources", systemImage: "server.rack")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // View Mode
            Picker("View Mode", selection: $isListView) {
                Label("Grid", systemImage: "square.grid.2x2").tag(false)
                Label("List", systemImage: "list.bullet").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            
            // Settings
            Button(action: {
                onOpenSettings()
            }) {
                Label("Settings", systemImage: "gear")
            }
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Material.bar)
        .zIndex(1000)
    }
}

struct WelcomeView: View {
    var appState: AppState
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "tv.inset.filled")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 80, height: 80)
            .foregroundStyle(.tint)
            
            VStack(spacing: 10) {
                Text("Welcome to PlayIPTV")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Watch your favorite live TV, movies, and series\nfrom your Xtream or M3U providers.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Add Source") {
                appState.settingsTab = .sources
                openSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(50)
    }
}
