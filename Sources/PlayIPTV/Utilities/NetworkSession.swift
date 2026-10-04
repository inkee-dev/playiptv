import Foundation

private final class NetworkSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private var proxyUsername: String = ""
    private var proxyPassword: String = ""
    
    func updateCredentials(username: String, password: String) {
        proxyUsername = username
        proxyPassword = password
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        let isProxyAuth = method == NSURLAuthenticationMethodHTTPBasic
            || method == NSURLAuthenticationMethodHTTPDigest
            || method == NSURLAuthenticationMethodNTLM
        
        if isProxyAuth, !proxyUsername.isEmpty {
            completionHandler(.useCredential, URLCredential(user: proxyUsername, password: proxyPassword, persistence: .forSession))
            return
        }
        
        completionHandler(.performDefaultHandling, nil)
    }
}

@MainActor
final class NetworkSession {
    static let shared = NetworkSession()
    
    private let delegate = NetworkSessionDelegate()
    private var sessionStorage: URLSession?
    
    var session: URLSession {
        if let sessionStorage { return sessionStorage }
        rebuild()
        return sessionStorage!
    }
    
    private init() {
        rebuild()
    }
    
    func rebuild() {
        sessionStorage?.invalidateAndCancel()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        ProxySettings.shared.applyURLSessionConfiguration(config)
        delegate.updateCredentials(
            username: ProxySettings.shared.username,
            password: ProxySettings.shared.password
        )
        
        sessionStorage = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
    
    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
