import SwiftUI

struct SettingsView: View {
    @Bindable var appState: AppState
    
    var body: some View {
        TabView(selection: $appState.settingsTab) {
            GeneralSettingsView(appState: appState)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(AppState.SettingsTab.general)
            
            SourceSettingsView(appState: appState)
                .tabItem {
                    Label("Sources", systemImage: "server.rack")
                }
                .tag(AppState.SettingsTab.sources)
            
            AboutSettingsView(appState: appState)
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(AppState.SettingsTab.about)
        }
        .frame(width: 500, height: 520)
    }
}

struct GeneralSettingsView: View {
    @Bindable var appState: AppState
    @ObservedObject private var epgManager = EPGManager.shared
    @ObservedObject private var proxySettings = ProxySettings.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox(label: Label("Appearance", systemImage: "paintpalette")) {
                    VStack(alignment: .leading) {
                        Picker("Theme", selection: $appState.theme) {
                            ForEach(AppState.AppTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding()
                }
                
                GroupBox(label: Label("Network Proxy", systemImage: "network")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Use proxy", isOn: $proxySettings.enabled)
                        
                        Text("Routes source loading, EPG, and stream playback through the proxy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if proxySettings.enabled {
                            Picker("Type", selection: $proxySettings.type) {
                                ForEach(ProxyType.allCases) { type in
                                    Text(type.rawValue).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            HStack(spacing: 8) {
                                TextField("Host", text: $proxySettings.host)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Port", text: $proxySettings.port)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 72)
                            }
                            
                            HStack(spacing: 8) {
                                TextField("Username (optional)", text: $proxySettings.username)
                                    .textFieldStyle(.roundedBorder)
                                SecureField("Password", text: $proxySettings.password)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            if proxySettings.isActive {
                                Text("Active: \(proxySettings.summaryForDebug())")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("Enter host and port to enable.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
                
                GroupBox(label: Label("EPG (Electronic Program Guide)", systemImage: "list.bullet.rectangle")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configure an XMLTV EPG source to display current programs for Live TV channels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        TextField("EPG URL (XMLTV format)", text: Binding(
                            get: { appState.epgUrl ?? "" },
                            set: { appState.epgUrl = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        
                        Button("Refresh") {
                            if let url = appState.epgUrl, !url.isEmpty {
                                Task {
                                    await EPGManager.shared.loadGlobalEPG(from: url)
                                    appState.lastEPGUpdate = EPGManager.shared.lastUpdateTime
                                }
                            }
                        }
                        .disabled(appState.epgUrl?.isEmpty ?? true)
                    }
                    
                    // Refresh interval picker
                    HStack {
                        Text("Auto-Refresh:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $appState.epgRefreshInterval) {
                            ForEach(AppState.EPGRefreshInterval.allCases) { interval in
                                Text(interval.rawValue).tag(interval)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    
                    // Status display
                    HStack(spacing: 8) {
                        if EPGManager.shared.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                            Text("Loading EPG data...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let error = EPGManager.shared.lastError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let lastUpdate = appState.lastEPGUpdate {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Last updated: \(lastUpdate, style: .relative) ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            }
            .padding()
        }
    }
}

struct SourceSettingsView: View {
    @Bindable var appState: AppState
    @ObservedObject private var epgManager = EPGManager.shared
    @Environment(\.openWindow) private var openWindow
    @State private var showingAddSource = false
    @State private var editingSource: Source?
    
    var body: some View {
        VStack(spacing: 0) {
            List {
                if !appState.sources.isEmpty {
                    ForEach(appState.sources) { source in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.name)
                                    .font(.headline)
                                Text(source.type == .m3u ? "M3U Playlist" : "Xtream Codes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                // Show status and stats
                                if appState.loadingSources.contains(source.id) {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 12, height: 12)
                                        Text("Loading...")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.top, 2)
                                } else if let content = appState.sourceContent[source.id] {
                                    // Count channels by category type for THIS source
                                    let liveCategories = Set(content.categories.filter { $0.type == .live }.map { $0.id })
                                    let movieCategories = Set(content.categories.filter { $0.type == .movie }.map { $0.id })
                                    let seriesCategories = Set(content.categories.filter { $0.type == .series }.map { $0.id })
                                    
                                    let liveCount = content.channels.filter { liveCategories.contains($0.categoryId) }.count
                                    let movieCount = content.channels.filter { movieCategories.contains($0.categoryId) }.count
                                    let seriesCount = content.channels.filter { seriesCategories.contains($0.categoryId) }.count
                                    
                                    HStack(spacing: 12) {
                                        if liveCount > 0 {
                                            Label("\(liveCount)", systemImage: "tv")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .help("\(liveCount) Live Channels")
                                        }
                                        if movieCount > 0 {
                                            Label("\(movieCount)", systemImage: "film")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .help("\(movieCount) Movies")
                                        }
                                        if seriesCount > 0 {
                                            Label("\(seriesCount)", systemImage: "tv.and.mediabox")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .help("\(seriesCount) Series")
                                        }
                                    }
                                    .padding(.top, 2)
                                    
                                    if let error = appState.sourceLoadErrors[source.id] {
                                        Text(error)
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .lineLimit(2)
                                            .padding(.top, 2)
                                    }
                                    
                                    // EPG Status
                                    if source.epgUrl != nil {
                                        HStack(spacing: 6) {
                                            if EPGManager.shared.loadingSourceIds.contains(source.id) {
                                                ProgressView()
                                                    .scaleEffect(0.6)
                                                    .frame(width: 12, height: 12)
                                                Text("Loading EPG...")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            } else if let error = EPGManager.shared.sourceErrors[source.id] {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.orange)
                                                Text("EPG Error")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .help(error)
                                            } else if EPGManager.shared.sourceUpdateTimes[source.id] != nil {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.green)
                                                Text("EPG Loaded")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.top, 2)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // Refresh Button (always available)
                            Button(action: {
                                Task {
                                    // Reload source content (channels/VODs)
                                    await appState.loadSource(source)
                                    
                                    // Reload EPG if configured
                                    if let epgUrl = source.epgUrl {
                                        await EPGManager.shared.loadEPG(for: source.id, from: epgUrl)
                                    }
                                }
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Refresh source content and EPG")
                            
                            // Status Icon
                            if !appState.loadingSources.contains(source.id) {
                                if let error = appState.sourceLoadErrors[source.id] {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .help(error)
                                } else if (appState.sourceContent[source.id]?.channels.isEmpty ?? true) {
                                    Image(systemName: "questionmark.circle")
                                        .foregroundStyle(.secondary.opacity(0.5))
                                } else {
                                    Image(systemName: "checkmark.circle")
                                        .foregroundStyle(.secondary.opacity(0.5))
                                }
                            }
                        }
                        .contextMenu {
                            Button("Edit") {
                                editingSource = source
                            }
                            Button("Delete", role: .destructive) {
                                appState.removeSource(source)
                            }
                        }
                        .onTapGesture {
                            editingSource = source
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            appState.removeSource(appState.sources[index])
                        }
                    }
                }
            }
            .overlay {
                if appState.sources.isEmpty {
                    ContentUnavailableView("No Sources", systemImage: "tv.slash", description: Text("Add an IPTV source to get started."))
                }
            }
            // Footer Bar
            HStack {
                Button(action: { showingAddSource = true }) {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                
                Spacer()
                
                Text("\(appState.sources.count) sources")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: {
                    openWindow(id: "debug")
                }) {
                    Image(systemName: "ant")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("Connection Debug")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Material.bar)
            
            Divider()
        }
        .sheet(isPresented: $showingAddSource) {
            AddSourceView(appState: appState)
        }
        .sheet(item: $editingSource) { source in
            EditSourceView(appState: appState, source: source)
        }
    }
}

struct AddSourceView: View {
    @Bindable var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = "My Playlist"
    @State private var sourceType: StreamType = .m3u
    @State private var m3uUrl: String = ""
    @State private var xtreamUrl: String = ""
    @State private var xtreamUsername: String = ""
    @State private var xtreamPassword: String = ""
    @State private var epgUrl: String = ""
    @State private var epgRefreshInterval: String = AppState.EPGRefreshInterval.twentyFourHours.rawValue
    @FocusState private var isNameFieldFocused: Bool
    @State private var validationError: String?
    
    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("", text: $name)
                    .focused($isNameFieldFocused)
                    .lineLimit(1)
            }
            
            Picker("", selection: $sourceType) {
                Text("M3U Playlist").tag(StreamType.m3u)
                Text("Xtream Codes").tag(StreamType.xtream)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            if sourceType == .m3u {
                VStack(alignment: .leading, spacing: 4) {
                    Text("M3U URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("", text: $m3uUrl)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Server URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("", text: $xtreamUrl)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Username")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("", text: $xtreamUsername)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Password")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SecureField("", text: $xtreamPassword)
                        .lineLimit(1)
                }
            }
            
            Divider()
                .padding(.vertical, 5)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("EPG URL (XMLTV)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Optional - Falls back to global EPG", text: $epgUrl)
                    .lineLimit(1)
                Text("Leave empty to use global EPG from General settings")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("EPG Auto-Refresh")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: $epgRefreshInterval) {
                    ForEach(AppState.EPGRefreshInterval.allCases) { interval in
                        Text(interval.rawValue).tag(interval.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            
            if let error = validationError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Add") {
                    if validateAndAdd() {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 400, maxWidth: 500)
        .onAppear {
            isNameFieldFocused = true
        }
    }
    
    private func validateAndAdd() -> Bool {
        validationError = nil
        
        // Validate name
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationError = "Name is required"
            return false
        }
        
        if sourceType == .m3u {
            // Validate M3U URL
            guard !m3uUrl.trimmingCharacters(in: .whitespaces).isEmpty else {
                validationError = "M3U URL is required"
                return false
            }
            
            guard let url = URL(string: m3uUrl.trimmingCharacters(in: .whitespaces)),
                  url.scheme != nil else {
                validationError = "Invalid M3U URL format"
                return false
            }
            
            let source = Source(
                name: name.trimmingCharacters(in: .whitespaces),
                type: .m3u,
                m3uUrl: m3uUrl.trimmingCharacters(in: .whitespaces),
                epgUrl: epgUrl.isEmpty ? nil : epgUrl.trimmingCharacters(in: .whitespaces),
                epgRefreshInterval: epgRefreshInterval
            )
            appState.addSource(source)
        } else {
            // Validate Xtream fields
            guard !xtreamUrl.trimmingCharacters(in: .whitespaces).isEmpty else {
                validationError = "Server URL is required"
                return false
            }
            
            guard let url = URL(string: xtreamUrl.trimmingCharacters(in: .whitespaces)),
                  url.scheme != nil else {
                validationError = "Invalid Server URL format"
                return false
            }
            
            guard !xtreamUsername.trimmingCharacters(in: .whitespaces).isEmpty else {
                validationError = "Username is required"
                return false
            }
            
            guard !xtreamPassword.isEmpty else {
                validationError = "Password is required"
                return false
            }
            
            let source = Source(
                name: name.trimmingCharacters(in: .whitespaces),
                type: .xtream,
                xtreamUrl: xtreamUrl.trimmingCharacters(in: .whitespaces),
                xtreamUser: xtreamUsername.trimmingCharacters(in: .whitespaces),
                xtreamPass: xtreamPassword,
                epgUrl: epgUrl.isEmpty ? nil : epgUrl.trimmingCharacters(in: .whitespaces),
                epgRefreshInterval: epgRefreshInterval
            )
            appState.addSource(source)
        }
        
        return true
    }
}
