import SwiftUI

struct EpisodeListView: View {
    @Bindable var appState: AppState
    let series: Channel
    let onBack: () -> Void
    
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if let logoUrl = series.logoUrl {
                    AsyncImage(url: logoUrl) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "tv.and.mediabox")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(series.name)
                        .font(.headline)
                    Text("\(appState.episodesForSeries.count) Episodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Episodes list
            if appState.isLoadingEpisodes {
                VStack {
                    Spacer()
                    ProgressView("Loading episodes...")
                    Spacer()
                }
            } else if appState.episodesForSeries.isEmpty {
                VStack {
                    Spacer()
                    Text("No episodes found")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                let sortedSeasons = groupedEpisodes.keys.sorted()
                List {
                    ForEach(sortedSeasons, id: \.self) { season in
                        Section("Season \(season)") {
                            ForEach(groupedEpisodes[season] ?? []) { episode in
                                EpisodeRow(
                                    episode: episode,
                                    series: series,
                                    sourceUrl: appState.sources.first(where: { $0.id == series.sourceId })?.url?.absoluteString,
                                    hasProgress: hasProgress(for: episode),
                                    onPlay: {
                                        playEpisode(episode)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var groupedEpisodes: [Int: [Episode]] {
        Dictionary(grouping: appState.episodesForSeries, by: { $0.seasonNum })
    }
    
    private func hasProgress(for episode: Episode) -> Bool {
        if let position = PlaybackPositionManager.shared.getPosition(streamId: episode.id),
           position > 5 {
            return true
        }
        return false
    }
    
    private func playEpisode(_ episode: Episode) {
        print("DEBUG: Playing episode \(episode.episodeNum) from season \(episode.seasonNum)")
        
        // Track current series and episode for navigation
        appState.currentSeriesId = series.streamId
        appState.currentEpisode = episode
        
        // Create a temporary channel for the episode
        let episodeChannel = Channel(
            sourceId: series.sourceId,
            streamId: episode.id,
            name: "\(series.name) - S\(episode.seasonNum)E\(episode.episodeNum)",
            logoUrl: series.logoUrl,
            streamUrl: episode.streamUrl,
            categoryId: series.categoryId,
            groupTitle: series.groupTitle,
            isSeries: false
        )
        
        // Call centralized selectChannel logic which now handles VOD confirmation for series/movies
        appState.selectChannel(episodeChannel)
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let series: Channel
    let sourceUrl: String?
    let hasProgress: Bool
    let onPlay: () -> Void
    
    @ObservedObject private var positionManager = PlaybackPositionManager.shared
    @ObservedObject private var favoritesManager = FavoritesManager.shared
    
    private var progress: Double {
        positionManager.getProgress(streamId: episode.id) ?? 0
    }
    
    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Episode \(episode.episodeNum)")
                            .font(.headline)
                        
                        if let title = episode.title {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "play.circle")
                        .foregroundStyle(.blue)
                }
                
                // Progress bar
                if progress > 0 {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)
                            
                            Rectangle()
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * progress, height: 4)
                        }
                        .cornerRadius(2)
                    }
                    .frame(height: 4)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let sourceUrl = sourceUrl {
                let isFavorited = favoritesManager.isFavorite(streamId: series.streamId, sourceUrl: sourceUrl)
                Button(action: {
                    favoritesManager.toggleFavorite(channel: series, sourceUrl: sourceUrl)
                }) {
                    Label(isFavorited ? "Remove Series from Favorites" : "Add Series to Favorites", 
                          systemImage: isFavorited ? "heart.slash" : "heart")
                }
            }
        }
    }
}
