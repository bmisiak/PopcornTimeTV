import Foundation

protocol CatalogProviding {
    func loadMovies(
        page: Int,
        filter: Popcorn.Filters,
        genre: Popcorn.Genres,
        searchTerm: String?,
        order: Popcorn.Orders
    ) async throws -> [Movie]

    func loadShows(
        page: Int,
        filter: Popcorn.Filters,
        genre: Popcorn.Genres,
        searchTerm: String?,
        order: Popcorn.Orders
    ) async throws -> [Show]

    func movieDetails(imdbID: String) async throws -> Movie
    func showDetails(imdbID: String) async throws -> Show
    func movieRecommendations(for movie: Movie) async throws -> [Movie]
    func showRecommendations(for show: Show) async throws -> [Show]
    func credits(for media: Media) async throws -> MediaCredits
    func searchPeople(query: String) async throws -> [Person]
    func movieCredits(for person: Person) async throws -> [Movie]
    func showCredits(for person: Person) async throws -> [Show]
}

public struct MediaCredits {
    public let actors: [Actor]
    public let crew: [Crew]

    public init(actors: [Actor], crew: [Crew]) {
        self.actors = actors
        self.crew = crew
    }
}

enum CatalogProvider {
    /// Change this single dependency to switch the complete catalog implementation.
    static let current: CatalogProviding = TMDBCatalogProvider()
}

struct TMDBCatalogProvider: CatalogProviding {
    func loadMovies(
        page: Int,
        filter: Popcorn.Filters,
        genre: Popcorn.Genres,
        searchTerm: String?,
        order: Popcorn.Orders
    ) async throws -> [Movie] {
        try await TMDBCatalogApi.shared.loadMovies(
            page: page,
            filter: filter,
            genre: genre,
            searchTerm: searchTerm
        )
    }

    func loadShows(
        page: Int,
        filter: Popcorn.Filters,
        genre: Popcorn.Genres,
        searchTerm: String?,
        order: Popcorn.Orders
    ) async throws -> [Show] {
        try await TMDBCatalogApi.shared.loadShows(
            page: page,
            filter: filter,
            genre: genre,
            searchTerm: searchTerm
        )
    }

    func movieDetails(imdbID: String) async throws -> Movie {
        try await TMDBCatalogApi.shared.movie(imdbID: imdbID)
    }

    func showDetails(imdbID: String) async throws -> Show {
        try await TMDBCatalogApi.shared.show(imdbID: imdbID)
    }

    func movieRecommendations(for movie: Movie) async throws -> [Movie] {
        guard let tmdbID = movie.tmdbId else { return [] }
        return try await TMDBCatalogApi.shared.movieRecommendations(tmdbID: tmdbID)
    }

    func showRecommendations(for show: Show) async throws -> [Show] {
        guard let tmdbID = show.tmdbId else { return [] }
        return try await TMDBCatalogApi.shared.showRecommendations(tmdbID: tmdbID)
    }

    func credits(for media: Media) async throws -> MediaCredits {
        guard let tmdbID = media.tmdbId else { return MediaCredits(actors: [], crew: []) }
        let type: TMDB.MediaType = media is Movie ? .movies : .shows
        return try await TMDBCatalogApi.shared.credits(type: type, tmdbID: tmdbID)
    }

    func searchPeople(query: String) async throws -> [Person] {
        try await TMDBCatalogApi.shared.searchPeople(query: query)
    }

    func movieCredits(for person: Person) async throws -> [Movie] {
        try await TMDBCatalogApi.shared.movieCredits(personID: person.tmdbId)
    }

    func showCredits(for person: Person) async throws -> [Show] {
        try await TMDBCatalogApi.shared.showCredits(personID: person.tmdbId)
    }
}

struct PopcornCatalogProvider: CatalogProviding {
    func loadMovies(
        page: Int,
        filter: Popcorn.Filters,
        genre: Popcorn.Genres,
        searchTerm: String?,
        order: Popcorn.Orders
    ) async throws -> [Movie] {
        try await performWithServerFailover {
            try await PopcornApi.shared.load(
                page,
                filterBy: filter,
                genre: genre,
                searchTerm: searchTerm,
                orderBy: order
            )
        }
    }

    func loadShows(
        page: Int,
        filter: Popcorn.Filters,
        genre: Popcorn.Genres,
        searchTerm: String?,
        order: Popcorn.Orders
    ) async throws -> [Show] {
        try await performWithServerFailover {
            try await PopcornApi.shared.load(
                page,
                filterBy: filter,
                genre: genre,
                searchTerm: searchTerm,
                orderBy: order
            )
        }
    }

    func movieDetails(imdbID: String) async throws -> Movie {
        try await performWithServerFailover {
            try await PopcornApi.shared.getInfo(imdbID)
        }
    }

    func showDetails(imdbID: String) async throws -> Show {
        try await performWithServerFailover {
            try await PopcornApi.shared.getInfo(imdbID)
        }
    }

    func movieRecommendations(for movie: Movie) async throws -> [Movie] {
        try await TraktApi.shared.getRelated(movie)
    }

    func showRecommendations(for show: Show) async throws -> [Show] {
        try await TraktApi.shared.getRelated(show)
    }

    func credits(for media: Media) async throws -> MediaCredits {
        let type: Trakt.MediaType = media is Movie ? .movies : .shows
        let people = try await TraktApi.shared.getPeople(forMediaOfType: type, id: media.id)
        return MediaCredits(actors: people.actors, crew: people.crew)
    }

    func searchPeople(query: String) async throws -> [Person] {
        try await TraktApi.shared.search(forPerson: query)
    }

    func movieCredits(for person: Person) async throws -> [Movie] {
        try await TraktApi.shared.getMediaCredits(forPersonWithId: person.imdbId, mediaType: Movie.self)
    }

    func showCredits(for person: Person) async throws -> [Show] {
        try await TraktApi.shared.getMediaCredits(forPersonWithId: person.imdbId, mediaType: Show.self)
    }

    private func performWithServerFailover<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            guard shouldAttemptServerFailover(for: error), await handleServerWasMoved() else {
                throw error
            }
            return try await operation()
        }
    }

    private func shouldAttemptServerFailover(for error: Error) -> Bool {
        if error is CancellationError {
            return false
        }

        if let urlError = error as? URLError {
            return urlError.code != .cancelled && urlError.code != .notConnectedToInternet
        }

        if let apiError = error as? APIError {
            switch apiError.type {
            case .unacceptableStatusCode(let code):
                return code >= 500
            case .invalidHttpStatusCode, .missingContent, .couldNotDecodeResponse:
                return true
            case .missingSession, .unkown:
                return false
            }
        }

        return error is DecodingError
    }
}
