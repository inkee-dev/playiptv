import Foundation

struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let htmlUrl: String
    let body: String?
    let publishedAt: String
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case body
        case publishedAt = "published_at"
    }
}

@MainActor
class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    
    @Published var isChecking: Bool = false
    @Published var latestRelease: GitHubRelease?
    @Published var checkError: String?
    
    private let githubRepo = "inkee08/playiptv"
    private let userDefaults = UserDefaults.standard
    private let lastCheckKey = "lastUpdateCheckDate"
    private let skippedVersionKey = "skippedVersion"
    
    private init() {}
    
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var skippedVersion: String? {
        get { userDefaults.string(forKey: skippedVersionKey) }
        set { userDefaults.set(newValue, forKey: skippedVersionKey) }
    }
    
    var lastCheckDate: Date? {
        get { userDefaults.object(forKey: lastCheckKey) as? Date }
        set { userDefaults.set(newValue, forKey: lastCheckKey) }
    }
    
    var shouldCheckForUpdates: Bool {
        guard let lastCheck = lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) > 86400 // 24 hours
    }
    
    func checkForUpdates() async {
        isChecking = true
        checkError = nil
        
        do {
            let release = try await fetchLatestRelease()
            latestRelease = release
            lastCheckDate = Date()
            
            print("DEBUG: Update Check - Current: \(currentVersion), Latest: \(release.tagName)")
        } catch {
            checkError = error.localizedDescription
            print("DEBUG: Update Check Error: \(error)")
        }
        
        isChecking = false
    }
    
    private func fetchLatestRelease() async throws -> GitHubRelease {
        // Use /releases endpoint instead of /releases/latest to include pre-releases
        let url = URL(string: "https://api.github.com/repos/\(githubRepo)/releases")!
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let (data, response) = try await NetworkSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // Handle specific error codes
        if httpResponse.statusCode == 404 {
            throw NSError(domain: "UpdateChecker", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No releases found on GitHub"
            ])
        } else if httpResponse.statusCode != 200 {
            throw NSError(domain: "UpdateChecker", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "GitHub API returned status code \(httpResponse.statusCode)"
            ])
        }
        
        // Decode array of releases
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        
        // Return the first release (most recent)
        guard let latestRelease = releases.first else {
            throw NSError(domain: "UpdateChecker", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No releases found on GitHub"
            ])
        }
        
        return latestRelease
    }
    
    func isUpdateAvailable() -> Bool {
        guard let latest = latestRelease else { return false }
        
        // Skip if user chose to skip this version
        if let skipped = skippedVersion, skipped == latest.tagName {
            return false
        }
        
        return compareVersions(current: currentVersion, latest: latest.tagName)
    }
    
    private func compareVersions(current: String, latest: String) -> Bool {
        // Remove 'v' prefix if present
        let currentClean = current.hasPrefix("v") ? String(current.dropFirst()) : current
        let latestClean = latest.hasPrefix("v") ? String(latest.dropFirst()) : latest
        
        // Split version and pre-release (e.g., "1.0.0-alpha.1" -> ["1.0.0", "alpha.1"])
        let currentComponents = currentClean.split(separator: "-", maxSplits: 1)
        let latestComponents = latestClean.split(separator: "-", maxSplits: 1)
        
        let currentVersion = String(currentComponents[0])
        let latestVersion = String(latestComponents[0])
        
        let currentParts = currentVersion.split(separator: ".").compactMap { Int($0) }
        let latestParts = latestVersion.split(separator: ".").compactMap { Int($0) }
        
        // Compare version numbers
        for i in 0..<max(currentParts.count, latestParts.count) {
            let currentPart = i < currentParts.count ? currentParts[i] : 0
            let latestPart = i < latestParts.count ? latestParts[i] : 0
            
            if latestPart > currentPart {
                return true
            } else if latestPart < currentPart {
                return false
            }
        }
        
        // If version numbers are equal, check pre-release
        // No pre-release (stable) > pre-release (alpha/beta/rc)
        let currentHasPreRelease = currentComponents.count > 1
        let latestHasPreRelease = latestComponents.count > 1
        
        if !currentHasPreRelease && latestHasPreRelease {
            // Current is stable, latest is pre-release -> no update
            return false
        } else if currentHasPreRelease && !latestHasPreRelease {
            // Current is pre-release, latest is stable -> update available
            return true
        } else if currentHasPreRelease && latestHasPreRelease {
            // Both are pre-releases, compare alphabetically
            let currentPreRelease = String(currentComponents[1])
            let latestPreRelease = String(latestComponents[1])
            return latestPreRelease > currentPreRelease
        }
        
        return false
    }
    
    func skipVersion(_ version: String) {
        skippedVersion = version
    }
    
    func resetSkippedVersion() {
        skippedVersion = nil
    }
}
