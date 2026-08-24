import SwiftUI

struct DebugWindowView: View {
    @Bindable var appState: AppState
    @ObservedObject private var log = DebugLog.shared
    
    @State private var levelFilter: DebugLogLevel? = nil
    @State private var sourceFilter: String? = nil
    
    private var sourceNames: [String] {
        let fromSources = appState.sources.map(\.name)
        let fromLog = log.entries.compactMap(\.source)
        return Array(Set(fromSources + fromLog)).sorted()
    }
    
    private var visibleEntries: [DebugLogEntry] {
        log.entries.filter { entry in
            if let levelFilter, entry.level != levelFilter { return false }
            if let sourceFilter, entry.source != sourceFilter { return false }
            return true
        }
    }
    
    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 12) {
                diagnosisCard
                sourcesCard
            }
            .padding(16)
            .frame(minHeight: 180)
            
            logCard
                .padding([.horizontal, .bottom], 16)
                .frame(minHeight: 220)
        }
        .frame(minWidth: 680, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var diagnosis: ListDiagnosis {
        appState.listDiagnosis
    }
    
    private var diagnosisCard: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: diagnosisIcon)
                    .font(.title2)
                    .foregroundStyle(diagnosisColor)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Channel list")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(diagnosis.title)
                        .font(.headline)
                    Text(diagnosis.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                
                Spacer()
                
                if let source = appState.selectedSource {
                    Button("Reload Source") {
                        Task { await appState.loadSource(source) }
                    }
                    .disabled(appState.loadingSources.contains(source.id))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Why the list is empty", systemImage: "list.bullet.rectangle")
        }
    }
    
    private var diagnosisIcon: String {
        if diagnosis.isLoading { return "arrow.triangle.2.circlepath" }
        if diagnosis.isError { return "xmark.octagon.fill" }
        if diagnosis.isEmpty { return "tray" }
        return "checkmark.circle.fill"
    }
    
    private var diagnosisColor: Color {
        if diagnosis.isLoading { return .secondary }
        if diagnosis.isError { return .red }
        if diagnosis.isEmpty { return .orange }
        return .green
    }
    
    private var sourcesCard: some View {
        GroupBox {
            if appState.sources.isEmpty {
                Text("No sources configured.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else {
                VStack(spacing: 0) {
                    ForEach(appState.sources) { source in
                        sourceRow(source)
                        if source.id != appState.sources.last?.id {
                            Divider()
                        }
                    }
                }
            }
        } label: {
            Label("Sources", systemImage: "server.rack")
        }
    }
    
    private func sourceRow(_ source: Source) -> some View {
        let loading = appState.loadingSources.contains(source.id)
        let error = appState.sourceLoadErrors[source.id]
        let content = appState.sourceContent[source.id]
        let live = content?.channels.filter { $0.categoryId == "live_all" }.count ?? 0
        let movies = content?.channels.filter { $0.categoryId == "vod_all" }.count ?? 0
        let series = content?.channels.filter { $0.categoryId == "series_all" }.count ?? 0
        let total = content?.channels.count ?? 0
        let endpoint = source.type == .m3u ? source.m3uUrl : source.xtreamUrl
        
        return HStack(alignment: .top, spacing: 10) {
            statusDot(loading: loading, error: error, total: total)
                .padding(.top, 3)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(source.name)
                        .fontWeight(.semibold)
                    Text(source.type == .m3u ? "M3U" : "Xtream")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    if appState.selectedSource?.id == source.id {
                        Text("Selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if let endpoint {
                    Text(DebugLog.redact(endpoint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                
                if loading {
                    Text("Connecting…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                } else if content != nil {
                    Text("Loaded \(total) items  ·  \(live) live  ·  \(movies) movies  ·  \(series) series")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not loaded yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                Task { await appState.loadSource(source) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload this source")
            .disabled(loading)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
    
    private func statusDot(loading: Bool, error: String?, total: Int) -> some View {
        Group {
            if loading {
                ProgressView()
                    .controlSize(.small)
            } else if error != nil {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            } else if total > 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.orange)
            }
        }
        .frame(width: 16, height: 16)
    }
    
    private var logCard: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack {
                    Picker("Level", selection: $levelFilter) {
                        Text("All levels").tag(Optional<DebugLogLevel>.none)
                        ForEach(DebugLogLevel.allCases) { level in
                            Text(level.rawValue).tag(Optional(level))
                        }
                    }
                    .frame(width: 140)
                    
                    Picker("Source", selection: $sourceFilter) {
                        Text("All sources").tag(Optional<String>.none)
                        ForEach(sourceNames, id: \.self) { name in
                            Text(name).tag(Optional(name))
                        }
                    }
                    .frame(minWidth: 160)
                    
                    Spacer()
                    
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log.copyText(), forType: .string)
                    }
                    .disabled(log.entries.isEmpty)
                    
                    Button("Clear") {
                        log.clear()
                    }
                    .disabled(log.entries.isEmpty)
                }
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            if visibleEntries.isEmpty {
                                Text("No log entries yet. Add or reload a source to see connection attempts.")
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 12)
                            }
                            ForEach(visibleEntries) { entry in
                                logRow(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(8)
                    }
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: log.entries.count) { _, _ in
                        if let last = visibleEntries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .padding(8)
        } label: {
            Label("Connection log", systemImage: "text.alignleft")
        }
    }
    
    private func logRow(_ entry: DebugLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            
            Image(systemName: entry.level.symbolName)
                .foregroundStyle(levelColor(entry.level))
                .frame(width: 14)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.category)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    if let source = entry.source {
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(entry.message)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    private func levelColor(_ level: DebugLogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct DebugCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        CommandMenu("Debug") {
            Button("Connection Debug") {
                openWindow(id: "debug")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}
