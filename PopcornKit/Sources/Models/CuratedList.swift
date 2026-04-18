//
//  CuratedList.swift
//
//  Created for the Metacritic / Rotten Tomatoes curated-lists integration.
//  See worker-curated-lists/README.md for the backing service.
//

import Foundation

/// A curated-list entry as advertised by the Cloudflare worker registry
/// endpoint (`GET /lists`). The worker returns this lightweight shape so the
/// app can render a picker without pulling every list's items up front.
public struct CuratedListDefinition: Codable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let source: String
    public let kind: Kind

    public enum Kind: String, Codable {
        case movie
        case show
    }
}

/// A single IMDb-identified title inside a curated list. The worker has
/// already confirmed it is available on the PopcornTime catalog.
public struct CuratedListItem: Codable, Hashable, Identifiable {
    public let imdbId: String
    public let title: String
    public let year: Int?
    public let score: Int?

    public var id: String { imdbId }

    enum CodingKeys: String, CodingKey {
        case imdbId, title, year, score
    }
}

/// The enriched payload returned by `GET /lists/:id`.
public struct CuratedList: Codable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let source: String
    public let kind: CuratedListDefinition.Kind
    public let updatedAt: Date
    public let items: [CuratedListItem]
}
