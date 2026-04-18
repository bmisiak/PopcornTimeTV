//
//  CuratedListsApi.swift
//
//  Thin client for the Cloudflare worker defined in
//  `worker-curated-lists/`. It exposes curated movie/show lists scraped from
//  Metacritic / Rotten Tomatoes and pre-filtered to titles available on the
//  PopcornTime catalog.
//

import Foundation

open class CuratedListsApi {
    public static let shared = CuratedListsApi()

    let client: HttpClient

    public init(baseURL: String = CuratedLists.base) {
        self.client = HttpClient(config: HttpApiConfig(serverURL: baseURL))
    }

    /// Fetch the remotely-configured list registry. Adding a new source does
    /// not require an app release — the worker owns the registry.
    public func loadRegistry() async throws -> [CuratedListDefinition] {
        return try await client.request(.get, path: "/lists")
            .responseDecode(decoder: .iso8601)
    }

    /// Fetch a single curated list by id. The worker returns an already
    /// enriched + availability-filtered payload; the client just renders it.
    public func loadList(id: String) async throws -> CuratedList {
        return try await client.request(.get, path: "/lists/\(id)")
            .responseDecode(decoder: .iso8601)
    }

    /// Hydrates a curated list's IMDb-only items into full `Movie` objects by
    /// asking the Popcorn API for each title's detail payload. Skips failures
    /// so a single dead item does not break the whole list.
    public func hydrateMovies(_ list: CuratedList) async -> [Movie] {
        guard list.kind == .movie else { return [] }
        return await hydrate(list.items) { imdbId in
            try await getMovieInfo(imdbId)
        }
    }

    public func hydrateShows(_ list: CuratedList) async -> [Show] {
        guard list.kind == .show else { return [] }
        return await hydrate(list.items) { imdbId in
            try await getShowInfo(imdbId)
        }
    }

    private func hydrate<T>(
        _ items: [CuratedListItem],
        using fetch: @escaping (String) async throws -> T
    ) async -> [T] {
        await withTaskGroup(of: (Int, T?).self, returning: [T].self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    let value = try? await fetch(item.imdbId)
                    return (index, value)
                }
            }
            var indexed: [(Int, T)] = []
            for await (index, value) in group {
                if let value = value { indexed.append((index, value)) }
            }
            indexed.sort { $0.0 < $1.0 }
            return indexed.map { $0.1 }
        }
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
