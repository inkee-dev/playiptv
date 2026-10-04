import SwiftUI

struct EpisodePickerView: View {
    @Bindable var appState: AppState
    let series: Channel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let logoUrl = series.logoUrl {
                    AsyncImage(url: logoUrl) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "tv.and.mediabox")
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(series.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("\(appState.episodesForSeries.count) Episodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            
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
                                Button(action: {
                                    playEpisode(episode)
                                }) {
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
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }
    
    private var groupedEpisodes: [Int: [Episode]] {
        Dictionary(grouping: appState.episodesForSeries, by: { $0.seasonNum })
    }
    
    private func playEpisode(_ episode: Episode) {
        print("DEBUG: Playing episode \(episode.episodeNum) from season \(episode.seasonNum)")
        
        // Track current series and episode for navigation
        appState.currentSeriesId = series.streamId
        appState.currentEpisode = episode
        
        // Track in recent VOD
        if let source = appState.sources.first(where: { $0.id == series.sourceId }),
           let sourceUrlString = source.url?.absoluteString {
            RecentVODManager.shared.addRecentVOD(
                streamId: series.streamId,
                name: series.name,
                logoUrl: series.logoUrl,
                sourceUrl: sourceUrlString,
                isSeries: true
            )
        }
        
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
        
        appState.selectChannel(episodeChannel)
        dismiss()
    }
}
