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
