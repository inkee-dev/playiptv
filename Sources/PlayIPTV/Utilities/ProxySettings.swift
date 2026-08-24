import Foundation
import Combine

enum ProxyType: String, CaseIterable, Codable, Identifiable {
    case http = "HTTP"
    case socks5 = "SOCKS5"
    
    var id: String { rawValue }
}

@MainActor
final class ProxySettings: ObservableObject {
    static let shared = ProxySettings()
    
    static let didChangeNotification = Notification.Name("ProxySettingsDidChange")
    
    @Published var enabled: Bool {
        didSet { persist() }
    }
    @Published var type: ProxyType {
        didSet { persist() }
    }
    @Published var host: String {
        didSet { persist() }
    }
    @Published var port: String {
        didSet { persist() }
    }
    @Published var username: String {
        didSet { persist() }
    }
    @Published var password: String {
        didSet { persist() }
    }
    
    var isActive: Bool {
        enabled && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && portNumber != nil
    }
    
    var portNumber: Int? {
        Int(port.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    var hostTrimmed: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private let defaults = UserDefaults.standard
    private let enabledKey = "proxyEnabled"
    private let typeKey = "proxyType"
    private let hostKey = "proxyHost"
    private let portKey = "proxyPort"
    private let usernameKey = "proxyUsername"
    private let passwordKey = "proxyPassword"
    private var persistTask: Task<Void, Never>?
    
    private init() {
        enabled = defaults.bool(forKey: enabledKey)
        type = ProxyType(rawValue: defaults.string(forKey: typeKey) ?? "") ?? .http
        host = defaults.string(forKey: hostKey) ?? ""
        port = defaults.string(forKey: portKey) ?? ""
        username = defaults.string(forKey: usernameKey) ?? ""
        password = defaults.string(forKey: passwordKey) ?? ""
    }
    
    func applyURLSessionConfiguration(_ config: URLSessionConfiguration) {
        guard isActive, let port = portNumber else { return }
        
        var proxy: [String: Any] = [:]
        switch type {
        case .http:
            proxy[kCFNetworkProxiesHTTPEnable as String] = true
            proxy[kCFNetworkProxiesHTTPProxy as String] = hostTrimmed
            proxy[kCFNetworkProxiesHTTPPort as String] = port
            proxy[kCFNetworkProxiesHTTPSEnable as String] = true
            proxy[kCFNetworkProxiesHTTPSProxy as String] = hostTrimmed
            proxy[kCFNetworkProxiesHTTPSPort as String] = port
        case .socks5:
            proxy[kCFNetworkProxiesSOCKSEnable as String] = true
            proxy[kCFNetworkProxiesSOCKSProxy as String] = hostTrimmed
            proxy[kCFNetworkProxiesSOCKSPort as String] = port
        }
        
        if !username.isEmpty {
            proxy[kCFProxyUsernameKey as String] = username
            proxy[kCFProxyPasswordKey as String] = password
        }
        
        config.connectionProxyDictionary = proxy
    }
    
    /// VLC `:option=value` strings applied per media item.
    func vlcMediaOptions() -> [String] {
        guard isActive, let port = portNumber else { return [] }
        
        switch type {
        case .http:
            var value = "http://"
            if !username.isEmpty {
                value += "\(username):\(password)@"
            }
            value += "\(hostTrimmed):\(port)"
            return [":http-proxy=\(value)"]
        case .socks5:
            return [":socks=\(hostTrimmed):\(port)"]
        }
    }
    
    func summaryForDebug() -> String {
        guard isActive, let port = portNumber else { return "Proxy disabled" }
        let auth = username.isEmpty ? "" : " (auth)"
        return "\(type.rawValue) \(hostTrimmed):\(port)\(auth)"
    }
    
    private func persist() {
        defaults.set(enabled, forKey: enabledKey)
        defaults.set(type.rawValue, forKey: typeKey)
        defaults.set(host, forKey: hostKey)
        defaults.set(port, forKey: portKey)
        defaults.set(username, forKey: usernameKey)
        defaults.set(password, forKey: passwordKey)
        
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            
            DebugLog.shared.info("Proxy settings updated: \(summaryForDebug())", category: "Network")
            NetworkSession.shared.rebuild()
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}
