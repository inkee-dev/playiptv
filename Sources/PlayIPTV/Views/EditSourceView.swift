import SwiftUI

struct EditSourceView: View {
    @Bindable var appState: AppState
    let source: Source
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var epgUrl: String
    @State private var epgRefreshInterval: String
    @State private var m3uUrl: String
    @State private var xtreamUrl: String
    @State private var xtreamUsername: String
    @State private var xtreamPassword: String
    @State private var stalkerUrl: String
    @State private var stalkerMac: String
    @State private var stalkerLogin: String
    @State private var stalkerPassword: String
    @State private var validationError: String?
    
    init(appState: AppState, source: Source) {
        self.appState = appState
        self.source = source
        _name = State(initialValue: source.name)
        _epgUrl = State(initialValue: source.epgUrl ?? "")
        _epgRefreshInterval = State(initialValue: source.epgRefreshInterval ?? AppState.EPGRefreshInterval.twentyFourHours.rawValue)
        _m3uUrl = State(initialValue: source.m3uUrl ?? "")
        _xtreamUrl = State(initialValue: source.xtreamUrl ?? "")
        _xtreamUsername = State(initialValue: source.xtreamUser ?? "")
        _xtreamPassword = State(initialValue: source.xtreamPass ?? "")
        _stalkerUrl = State(initialValue: source.stalkerUrl ?? "")
        _stalkerMac = State(initialValue: source.stalkerMac ?? "")
        _stalkerLogin = State(initialValue: source.stalkerLogin ?? "")
        _stalkerPassword = State(initialValue: source.stalkerPassword ?? "")
    }
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Edit Source")
                .font(.headline)
                .padding(.bottom, 5)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("", text: $name)
                    .lineLimit(1)
            }
            
            switch source.type {
            case .m3u:
                VStack(alignment: .leading, spacing: 4) {
                    Text("M3U URL")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("", text: $m3uUrl)
                        .lineLimit(1)
                }
            case .xtream:
                Group {
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
            case .stalker:
                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Portal URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("http://example.com/stalker_portal/c/", text: $stalkerUrl)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MAC Address")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("00:1A:79:00:00:00", text: $stalkerMac)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Login (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("", text: $stalkerLogin)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField("", text: $stalkerPassword)
                            .lineLimit(1)
                    }
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
                
                Button("Save") {
                    if saveChanges() {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460, maxWidth: 560)
    }
    
    private func saveChanges() -> Bool {
        validationError = nil
        
        // Validate name
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationError = "Name is required"
            return false
        }
        
        // Find and update the source
        if let index = appState.sources.firstIndex(where: { $0.id == source.id }) {
            var updatedSource = appState.sources[index]
            updatedSource.name = name.trimmingCharacters(in: .whitespaces)
            updatedSource.epgUrl = epgUrl.isEmpty ? nil : epgUrl.trimmingCharacters(in: .whitespaces)
            updatedSource.epgRefreshInterval = epgRefreshInterval
            
            switch source.type {
            case .m3u:
                updatedSource.m3uUrl = m3uUrl.trimmingCharacters(in: .whitespaces)
            case .xtream:
                updatedSource.xtreamUrl = xtreamUrl.trimmingCharacters(in: .whitespaces)
                updatedSource.xtreamUser = xtreamUsername.trimmingCharacters(in: .whitespaces)
                updatedSource.xtreamPass = xtreamPassword
            case .stalker:
                guard let portal = StalkerLink.portalURL(from: stalkerUrl) else {
                    validationError = "Portal URL is required"
                    return false
                }
                guard let mac = StalkerLink.normalizeMAC(stalkerMac) else {
                    validationError = "Enter a valid MAC address, for example 00:1A:79:00:00:00"
                    return false
                }
                if stalkerLogin.trimmingCharacters(in: .whitespaces).isEmpty && !stalkerPassword.isEmpty {
                    validationError = "Login is required when a password is set"
                    return false
                }
                let login = stalkerLogin.trimmingCharacters(in: .whitespaces)
                updatedSource.stalkerUrl = portal.absoluteString
                updatedSource.stalkerMac = mac
                updatedSource.stalkerLogin = login.isEmpty ? nil : login
                updatedSource.stalkerPassword = stalkerPassword.isEmpty ? nil : stalkerPassword
            }
            
            
            appState.sources[index] = updatedSource
            if appState.selectedSource?.id == updatedSource.id {
                appState.selectedSource = updatedSource
            }
            
            // Save to UserDefaults and reload the catalog with the edited credentials
            let reloadedSource = updatedSource
            Task { @MainActor in
                if let data = try? JSONEncoder().encode(appState.sources) {
                    UserDefaults.standard.set(data, forKey: "savedSources")
                }
                await appState.loadSource(reloadedSource)
            }
            
            // Reload EPG if URL changed
            if updatedSource.epgUrl != source.epgUrl {
                if let newEpg = updatedSource.epgUrl, !newEpg.isEmpty {
                    Task {
                        await EPGManager.shared.loadEPG(for: updatedSource.id, from: newEpg)
                    }
                } else {
                    // Clear source-specific EPG
                    EPGManager.shared.clearEPG(for: updatedSource.id)
                }
            }
        }
        
        return true
    }
}
