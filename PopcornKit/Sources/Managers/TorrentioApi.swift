import Foundation

public final class TorrentioApi {
    public static let shared = TorrentioApi()

    private let baseURL: URL
    private let session: URLSession
    private let cache = NSCache<NSString, NSArray>()
    private let responseCacheLifetime: TimeInterval = 6 * 60 * 60

    public init(baseURL: URL = URL(string: "https://torrentio.strem.fun")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func streams(for media: Media) async throws -> [Torrent] {
        let type: String
        let identifier: String

        if let episode = media as? Episode, let showID = episode.show?.id, showID.hasPrefix("tt") {
            type = "series"
            identifier = "\(showID):\(episode.season):\(episode.episode)"
        } else if media is Movie, media.id.hasPrefix("tt") {
            type = "movie"
            identifier = media.id
        } else {
            throw TorrentioError.missingIMDbIdentifier
        }

        let cacheKey = "\(type)/\(identifier)" as NSString
        if let cached = cache.object(forKey: cacheKey) as? [Torrent] {
            return cached
        }

        let persistentCacheKey = "TorrentioApi.response.\(cacheKey)"
        if let cached = UserDefaults.standard.data(forKey: persistentCacheKey),
           let entry = try? JSONDecoder().decode(CachedResponse.self, from: cached),
           Date().timeIntervalSince(entry.date) < responseCacheLifetime,
           let payload = try? JSONDecoder().decode(StreamResponse.self, from: entry.data) {
            let torrents = payload.streams.compactMap(\.torrent)
            if !torrents.isEmpty {
                cache.setObject(torrents as NSArray, forKey: cacheKey)
                return torrents
            }
        }

        let url = baseURL
            .appendingPathComponent("stream")
            .appendingPathComponent(type)
            .appendingPathComponent(identifier + ".json")
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw TorrentioError.unavailable
        }

        let payload = try JSONDecoder().decode(StreamResponse.self, from: data)
        let torrents = payload.streams.compactMap(\.torrent).sorted {
            if $0.quality == $1.quality { return $0.seeds > $1.seeds }
            return $0 > $1
        }
        guard !torrents.isEmpty else {
            throw TorrentioError.noStreams
        }
        cache.setObject(torrents as NSArray, forKey: cacheKey)
        if let cached = try? JSONEncoder().encode(CachedResponse(date: Date(), data: data)) {
            UserDefaults.standard.set(cached, forKey: persistentCacheKey)
        }
        return torrents
    }
}

private struct CachedResponse: Codable {
    let date: Date
    let data: Data
}

public enum TorrentioError: LocalizedError {
    case missingIMDbIdentifier
    case unavailable
    case noStreams

    public var errorDescription: String? {
        switch self {
        case .missingIMDbIdentifier:
            return "An IMDb identifier is required to find streams."
        case .unavailable:
            return "The stream provider is temporarily unavailable."
        case .noStreams:
            return "No torrents were found for this title."
        }
    }
}

private struct StreamResponse: Decodable {
    let streams: [TorrentioStream]
}

private struct TorrentioStream: Decodable {
    struct BehaviorHints: Decodable {
        let filename: String?
    }

    let name: String?
    let title: String?
    let infoHash: String?
    let fileIdx: Int?
    let sources: [String]?
    let behaviorHints: BehaviorHints?

    var torrent: Torrent? {
        guard let infoHash, !infoHash.isEmpty else { return nil }
        let displayText = [name, title].compactMap { $0 }.joined(separator: " ")
        let filename = behaviorHints?.filename
        let magnet = Self.magnet(infoHash: infoHash, filename: filename, sources: sources ?? [])
        return Torrent(
            url: magnet,
            quality: Self.quality(in: displayText),
            seeds: Self.firstInteger(in: displayText, pattern: #"👤\s*(\d+)"#) ?? 0,
            size: Self.firstString(in: displayText, pattern: #"💾\s*([\d.]+\s*(?:GB|MB|TB))"#),
            fileIndex: fileIdx,
            filename: filename
        )
    }

    private static func magnet(infoHash: String, filename: String?, sources: [String]) -> String {
        var components = URLComponents()
        components.scheme = "magnet"
        components.queryItems = [URLQueryItem(name: "xt", value: "urn:btih:\(infoHash)")]
        if let filename, !filename.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "dn", value: filename))
        }
        for source in sources {
            let tracker = source.hasPrefix("tracker:") ? String(source.dropFirst("tracker:".count)) : source
            components.queryItems?.append(URLQueryItem(name: "tr", value: tracker))
        }
        return components.string ?? "magnet:?xt=urn:btih:\(infoHash)"
    }

    private static func quality(in text: String) -> String {
        let lowercased = text.lowercased()
        for quality in ["2160p", "1080p", "720p", "480p"] where lowercased.contains(quality) {
            return quality
        }
        return lowercased.contains("4k") ? "2160p" : "Unknown"
    }

    private static func firstInteger(in text: String, pattern: String) -> Int? {
        firstString(in: text, pattern: pattern).flatMap(Int.init)
    }

    private static func firstString(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

public enum TorrentFileSelector {
    public static func select(torrent: Torrent, media: Media, fileNames: [String], fileSizes: [NSNumber]) -> Int? {
        guard fileNames.count == fileSizes.count, !fileNames.isEmpty else { return nil }
        if fileNames.count == 1 { return 0 }

        if let episode = media as? Episode {
            if let index = torrent.fileIndex,
               fileNames.indices.contains(index),
               filename(fileNames[index], matches: torrent.filename),
               filenameMatchesEpisode(fileNames[index], season: episode.season, episode: episode.episode) {
                return index
            }

            let matches = fileNames.indices.filter {
                isPlayableVideo(fileNames[$0]) &&
                !isSample(fileNames[$0]) &&
                filenameMatchesEpisode(fileNames[$0], season: episode.season, episode: episode.episode)
            }
            return matches.max { fileSizes[$0].int64Value < fileSizes[$1].int64Value }
        }

        if let index = torrent.fileIndex,
           fileNames.indices.contains(index),
           filename(fileNames[index], matches: torrent.filename) {
            return index
        }
        return fileNames.indices.filter { isPlayableVideo(fileNames[$0]) && !isSample(fileNames[$0]) }
            .max { fileSizes[$0].int64Value < fileSizes[$1].int64Value }
    }

    private static func filename(_ actual: String, matches expected: String?) -> Bool {
        guard let expected else { return true }
        return URL(fileURLWithPath: actual).lastPathComponent.caseInsensitiveCompare(
            URL(fileURLWithPath: expected).lastPathComponent
        ) == .orderedSame
    }

    private static func filenameMatchesEpisode(_ filename: String, season: Int, episode: Int) -> Bool {
        let patterns = [
            String(format: #"(?i)(?:^|[^a-z0-9])s%02de%02d(?:e\d{2})?(?:[^a-z0-9]|$)"#, season, episode),
            String(format: #"(?i)(?:^|[^a-z0-9])%dx%02d(?:[^a-z0-9]|$)"#, season, episode)
        ]
        let range = NSRange(filename.startIndex..., in: filename)
        return patterns.contains { pattern in
            (try? NSRegularExpression(pattern: pattern).firstMatch(in: filename, range: range)) != nil
        }
    }

    private static func isPlayableVideo(_ filename: String) -> Bool {
        ["mkv", "mp4", "avi", "m4v", "mov", "ts"].contains(URL(fileURLWithPath: filename).pathExtension.lowercased())
    }

    private static func isSample(_ filename: String) -> Bool {
        filename.lowercased().contains("sample")
    }
}
