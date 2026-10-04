import SwiftUI

struct ChannelGridView: View {
    @Bindable var appState: AppState
    @Binding var isListView: Bool
    @State private var showEpisodePicker: Bool = false
    @State private var scrollPosition: UUID?
    @State private var scrollToId: UUID?
    @State private var shouldScrollToSelected = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    
    private var headerBackgroundColor: Color {
        if isListView {
            return Color(nsColor: .controlBackgroundColor)
        } else {
            return Color(nsColor: .windowBackgroundColor)
        }
    }
    
    private var contentBackgroundColor: Color {
        // Lighter background for content areas (works in light and dark mode)
        Color(nsColor: .textBackgroundColor)
    }
    
    // Create a scroll view ID based on category to maintain scroll position within a category
    private var scrollViewId: String {
        appState.selectedCategory?.id ?? "none"
    }
    
    var body: some View {
        Group {
            if appState.showingEpisodeList, let series = appState.episodeListSeries {
                EpisodeListView(
                    appState: appState,
                    series: series,
                    onBack: {
                        appState.showingEpisodeList = false
                        appState.episodeListSeries = nil
                    }
                )
            } else if isListView {
                listView
            } else {
                gridView
            }
        }
        .overlay {
            if !appState.showingEpisodeList && appState.filteredChannels.isEmpty {
                emptyListOverlay
            }
        }
        .navigationTitle(appState.showingEpisodeList ? "" : (appState.selectedCategory?.name ?? "All Channels"))
        .searchable(text: $appState.channelSearchText, placement: .toolbar, prompt: "Search channels...")
        .onChange(of: appState.selectedCategory) { oldValue, newValue in
            // Close episode list when category changes OR when clicking the same category
            if appState.showingEpisodeList {
                // Check if user clicked the parent category of the current series
                let clickedParentCategory = (newValue?.id == appState.episodeListParentCategory?.id)
                
                // Close if different category OR if clicking the parent category again
                if oldValue?.id != newValue?.id || clickedParentCategory {
                    appState.showingEpisodeList = false
                    appState.episodeListSeries = nil
                }
            }
        }
    }
    
    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Show clear button for Recent category
                    if appState.selectedCategory?.id == "recent" && !appState.filteredChannels.isEmpty {
                        Button(action: {
                            RecentVODManager.shared.clearAll()
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                                Text("Clear Recent")
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding()
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                    
                    
                    ForEach(appState.filteredChannels) { channel in
                        ChannelRowView(
                            channel: channel,
                            appState: appState
                        )
                        .id(channel.id.uuidString)
                        
                        Divider()
                    }
                }
            }
            .id(scrollViewId)  // Reset scroll for categories without selected channel
            .onChange(of: appState.selectedCategory?.id) { oldValue, newValue in
                // When switching categories, scroll to selected channel if it's in this category
                if let selectedChannel = appState.selectedChannel,
                   appState.filteredChannels.contains(where: { $0.id == selectedChannel.id }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo(selectedChannel.id.uuidString, anchor: .center)
                    }
                }
            }
            .onChange(of: appState.channelSearchText) { oldValue, newValue in
                // When search is cleared, scroll to selected channel with a slight delay
                if !oldValue.isEmpty && newValue.isEmpty {
                    if let selectedId = appState.selectedChannel?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            proxy.scrollTo(selectedId.uuidString, anchor: .center)
                        }
                    }
                }
            }
            .onAppear {
                // When list view appears, scroll to selected channel
                if let selectedId = appState.selectedChannel?.id {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo(selectedId.uuidString, anchor: .center)
                    }
                }
            }
            .background(contentBackgroundColor)
        }
    }
    
    private var gridView: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]
        
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Show clear button for Recent category
                    if appState.selectedCategory?.id == "recent" && !appState.filteredChannels.isEmpty {
                        HStack {
                            Spacer()
                            Button(action: {
                                RecentVODManager.shared.clearAll()
                            }) {
                                Label("Clear Recent", systemImage: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.bordered)
                            .padding()
                        }
                        .background(headerBackgroundColor)
                    }
                    
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(appState.filteredChannels) { channel in
                            ChannelButtonView(
                                channel: channel,
                                appState: appState
                            )
                            .id(channel.id.uuidString)
                        }
                    }
                    .padding()
                }
            }
            .id(scrollViewId)  // Reset scroll for categories without selected channel
            .onChange(of: appState.selectedCategory?.id) { oldValue, newValue in
                // When switching categories, scroll to selected channel if it's in this category
                if let selectedChannel = appState.selectedChannel,
                   appState.filteredChannels.contains(where: { $0.id == selectedChannel.id }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo(selectedChannel.id.uuidString, anchor: .center)
                    }
                }
            }
            .onChange(of: appState.channelSearchText) { oldValue, newValue in
                // When search is cleared, scroll to selected channel with a slight delay
                if !oldValue.isEmpty && newValue.isEmpty {
                    if let selectedId = appState.selectedChannel?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            proxy.scrollTo(selectedId.uuidString, anchor: .center)
                        }
                    }
                }
            }
            .onAppear {
                // When grid view appears, scroll to selected channel
                if let selectedId = appState.selectedChannel?.id {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo(selectedId.uuidString, anchor: .center)
                    }
                }
            }
            .background(contentBackgroundColor)
        }
    }
    
    private var emptyListOverlay: some View {
        let diagnosis = appState.listDiagnosis
        return VStack(spacing: 12) {
            if diagnosis.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: diagnosis.isError ? "exclamationmark.triangle" : "tray")
                    .font(.system(size: 28))
                    .foregroundStyle(diagnosis.isError ? .orange : .secondary)
            }
            
            Text(diagnosis.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text(diagnosis.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            
            Button("Open Connection Debug") {
                openWindow(id: "debug")
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
    }
    
    private func handleChannelTap(_ channel: Channel) {
        if channel.isSeries {
            Task {
                await appState.fetchEpisodesForSeries(channel)
                appState.episodeListSeries = channel
                appState.showingEpisodeList = true
            }
        } else {
            appState.selectChannel(channel)
        }
    }
}

struct ChannelCard: View {
    let channel: Channel
    let epgProgram: EPGProgram?
    let isSelected: Bool
    let isLoading: Bool
    
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.3))
                .frame(height: 100)
                .overlay {
                    Image(systemName: "tv")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(20)
                        .foregroundStyle(.secondary)
                }
            
            Text(channel.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            
            // Loading indicator for series
            if isLoading {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 10, height: 10)
                    Text("Loading...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // EPG Program info (Live TV only)
            if let program = epgProgram {
                Text(program.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
            }
            
            // Progress bar (VOD only)
            if channel.isVODPlayback {
                let progress = PlaybackPositionManager.shared.getProgress(streamId: channel.streamId) ?? 0
                if progress > 0 {
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 3)
                        
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: 100 * progress, height: 3) // Assuming card width is roughly 100-120
                    }
                    .frame(maxWidth: 80) // Limit bar width
                    .cornerRadius(1.5)
                    .padding(.top, 2)
                }
            }
        }
        .padding()
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(16)
    }
}

struct ChannelButtonView: View {
    let channel: Channel
    var appState: AppState // Pass AppState by reference
    @ObservedObject var favoritesManager = FavoritesManager.shared
    
    var body: some View {
        let isSelected = appState.selectedChannel?.id == channel.id
        let isLoading = channel.isSeries && appState.isLoadingEpisodes && appState.selectedSeriesForEpisodes?.id == channel.id
        
        let cacheKey = "\(channel.sourceId.uuidString):\(channel.name)"
        let cachedProgram = appState.epgProgramCache[cacheKey]
        
        Button(action: {
            if channel.isSeries {
                Task {
                    await appState.fetchEpisodesForSeries(channel)
                    appState.episodeListSeries = channel
                    appState.showingEpisodeList = true
                }
            } else {
                appState.selectChannel(channel)
            }
        }) {
            ChannelCard(
                channel: channel,
                epgProgram: cachedProgram,
                isSelected: isSelected,
                isLoading: isLoading
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let source = appState.sources.first(where: { $0.id == channel.sourceId }),
               let sourceUrl = source.url?.absoluteString {
                let isFavorited = favoritesManager.isFavorite(streamId: channel.streamId, sourceUrl: sourceUrl)
                Button(action: {
                    favoritesManager.toggleFavorite(channel: channel, sourceUrl: sourceUrl)
                    Task { @MainActor in
                        appState.updateEPGCache()
                    }
                }) {
                    Label(isFavorited ? "Remove from Favorites" : "Add to Favorites", 
                          systemImage: isFavorited ? "heart.slash" : "heart")
                }
            }
        }
    }
}
