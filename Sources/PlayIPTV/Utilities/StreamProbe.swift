import Foundation

/// Reads just enough of a stream URL to explain why playback failed.
/// Call this after the player has released the connection. Many providers allow only one stream at a time.
enum StreamProbe {
    struct Report: Sendable {
        var summary: String
    }

    static func inspect(url: URL, userAgent: String?, referrer: String?) async -> Report {
        if url.isFileURL {
            let exists = FileManager.default.fileExists(atPath: url.path)
            return Report(summary: exists ? "Local file exists: \(url.path)" : "Local file is missing: \(url.path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue(userAgent ?? "PlayIPTV", forHTTPHeaderField: "User-Agent")
        if let referrer, !referrer.isEmpty {
            request.setValue(referrer, forHTTPHeaderField: "Referer")
        }

        let session = await NetworkSession.shared.session
        do {
            let (bytes, response) = try await session.bytes(for: request)
            var data = Data()
            var readError: String?
            do {
                for try await byte in bytes {
                    if Task.isCancelled { break }
                    data.append(byte)
                    if data.count >= 1024 { break }
                }
            } catch {
                if Task.isCancelled {
                    bytes.task.cancel()
                    return Report(summary: "Stream check cancelled")
                }
                if data.isEmpty {
                    readError = DebugLog.describe(error)
                }
            }
            bytes.task.cancel()
            if Task.isCancelled {
                return Report(summary: "Stream check cancelled")
            }
            return Report(summary: describe(response: response, data: data, readError: readError))
        } catch {
            if Task.isCancelled {
                return Report(summary: "Stream check cancelled")
            }
            return Report(summary: "Stream check failed: \(DebugLog.describe(error))")
        }
    }

    private static func describe(response: URLResponse, data: Data, readError: String?) -> String {
        var lines: [String] = []
        let http = response as? HTTPURLResponse
        if let http {
            let reason = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            lines.append("HTTP \(http.statusCode) \(reason)")
        } else {
            lines.append("Response was not HTTP")
        }

        if let finalURL = response.url {
            lines.append("Final URL: \(DebugLog.redact(finalURL))")
        }

        if let mime = http?.value(forHTTPHeaderField: "Content-Type"), !mime.isEmpty {
            lines.append("Content-Type: \(mime)")
        }
        if let server = http?.value(forHTTPHeaderField: "Server"), !server.isEmpty {
            lines.append("Server: \(server)")
        }
        if let length = http?.value(forHTTPHeaderField: "Content-Length"), !length.isEmpty {
            lines.append("Content-Length: \(length)")
        }

        lines.append("Looks like: \(sniff(data, mime: http?.value(forHTTPHeaderField: "Content-Type")))")
        lines.append("Read \(data.count) bytes, then stopped")

        if let preview = textPreview(data) {
            lines.append("Body: \(preview)")
        } else if !data.isEmpty {
            lines.append("First bytes: \(hexPrefix(data))")
        }

        if let readError {
            lines.append("Read error: \(readError)")
        }
        return lines.joined(separator: "\n")
    }

    private static func sniff(_ data: Data, mime: String?) -> String {
        if data.starts(with: Data("#EXTM3U".utf8)) { return "HLS playlist" }
        if data.first == 0x47 { return "MPEG-TS" }
        if data.count >= 8, data[4..<8].elementsEqual(Data("ftyp".utf8)) { return "MP4" }
        if data.starts(with: Data("ID3".utf8)) { return "audio (ID3)" }
        let prefix = String(data: data.prefix(32), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if prefix.hasPrefix("<") { return "HTML or XML" }
        if prefix.hasPrefix("{") || prefix.hasPrefix("[") { return "JSON" }
        if let mime, !mime.isEmpty { return mime }
        if data.isEmpty { return "empty response" }
        return "unrecognized binary"
    }

    private static func textPreview(_ data: Data) -> String? {
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        let sample = text.prefix(64)
        let printable = sample.allSatisfy { character in
            character.isLetter || character.isNumber || character.isPunctuation || character.isWhitespace || character.isSymbol
        }
        guard printable else { return nil }
        return DebugLog.preview(data, limit: 400)
    }

    private static func hexPrefix(_ data: Data) -> String {
        data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
