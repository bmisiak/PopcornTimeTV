import Foundation

final class TMDBCatalogApi {
    static let shared = TMDBCatalogApi()

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadMovies(page: Int, filter: Popcorn.Filters, genre: Popcorn.Genres, searchTerm: String?) async throws -> [Movie] {
        var query = ["page": String(page)]
        let path: String
        if let searchTerm, !searchTerm.isEmpty {
            path = "/search/movie"
            query["query"] = searchTerm
        } else {
            switch filter {
            case .trending: path = "/trending/movie/week"
            case .rating: path = "/movie/top_rated"
            case .year, .date: path = "/movie/now_playing"
            case .popularity: path = "/movie/popular"
            }
        }
        let page: CatalogPage = try await request(path, query: query)
        return try await withThrowingTaskGroup(of: (Int, Movie?).self) { group in
            for (index, item) in page.results.enumerated() where genre == .all || item.genreIDs.contains(genre.tmdbMovieID) {
                group.addTask { (index, try? await self.movie(id: item.id)) }
            }
            var movies = [(Int, Movie)]()
            for try await (index, movie) in group {
                if let movie { movies.append((index, movie)) }
            }
            return movies.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func loadShows(page: Int, filter: Popcorn.Filters, genre: Popcorn.Genres, searchTerm: String?) async throws -> [Show] {
        var query = ["page": String(page)]
        let path: String
        if let searchTerm, !searchTerm.isEmpty {
            path = "/search/tv"
            query["query"] = searchTerm
        } else {
            switch filter {
            case .trending: path = "/trending/tv/week"
            case .rating: path = "/tv/top_rated"
            case .year, .date: path = "/tv/on_the_air"
            case .popularity: path = "/tv/popular"
            }
        }
        let page: CatalogPage = try await request(path, query: query)
        return try await withThrowingTaskGroup(of: (Int, Show?).self) { group in
            for (index, item) in page.results.enumerated() where genre == .all || item.genreIDs.contains(genre.tmdbTVID) {
                group.addTask { (index, try? await self.show(id: item.id, includeEpisodes: false)) }
            }
            var shows = [(Int, Show)]()
            for try await (index, show) in group {
                if let show { shows.append((index, show)) }
            }
            return shows.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func movie(imdbID: String) async throws -> Movie {
        let result: FindResponse = try await request("/find/\(imdbID)", query: ["external_source": "imdb_id"])
        guard let id = result.movieResults.first?.id else { throw CatalogError.notFound }
        return try await movie(id: id)
    }

    func show(imdbID: String) async throws -> Show {
        let result: FindResponse = try await request("/find/\(imdbID)", query: ["external_source": "imdb_id"])
        guard let id = result.tvResults.first?.id else { throw CatalogError.notFound }
        return try await show(id: id, includeEpisodes: true)
    }

    private func movie(id: Int) async throws -> Movie {
        let detail: MovieDetail = try await request("/movie/\(id)", query: ["append_to_response": "external_ids,videos"])
        guard let imdbID = detail.externalIDs?.imdbID ?? detail.imdbID else { throw CatalogError.missingIMDbID }
        let trailer = detail.videos?.results.first(where: { $0.site == "YouTube" && $0.type == "Trailer" })?.key
        return Movie(
            title: detail.title,
            id: imdbID,
            tmdbId: detail.id,
            slug: detail.title.slugged,
            year: detail.releaseDate?.prefix(4).description ?? "",
            rating: detail.voteAverage * 10,
            runtime: detail.runtime ?? 0,
            genres: detail.genres.map(\.name),
            summary: detail.overview,
            trailer: trailer.map { "https://www.youtube.com/watch?v=\($0)" },
            largeBackgroundImage: imageURL(detail.backdropPath, size: "original"),
            largeCoverImage: imageURL(detail.posterPath, size: "w780")
        )
    }

    private func show(id: Int, includeEpisodes: Bool) async throws -> Show {
        let detail: ShowDetail = try await request("/tv/\(id)", query: ["append_to_response": "external_ids"])
        guard let imdbID = detail.externalIDs?.imdbID else { throw CatalogError.missingIMDbID }
        var show = Show(
            title: detail.name,
            id: imdbID,
            tmdbId: detail.id,
            tvdbId: detail.externalIDs?.tvdbID.map(String.init) ?? "0000000",
            slug: detail.name.slugged,
            year: detail.firstAirDate?.prefix(4).description ?? "",
            rating: detail.voteAverage * 10,
            runtime: detail.episodeRunTime.first,
            status: detail.status,
            genres: detail.genres.map(\.name),
            summary: detail.overview,
            largeBackgroundImage: imageURL(detail.backdropPath, size: "original"),
            largeCoverImage: imageURL(detail.posterPath, size: "w780")
        )
        guard includeEpisodes else { return show }

        let showWithoutEpisodes = show
        let episodes = try await withThrowingTaskGroup(of: [Episode].self) { group in
            for season in detail.seasons where season.seasonNumber >= 0 {
                group.addTask {
                    let seasonDetail: SeasonDetail = try await self.request("/tv/\(id)/season/\(season.seasonNumber)")
                    return seasonDetail.episodes.map { episode in
                        Episode(
                            title: episode.name,
                            id: String(episode.id),
                            tmdbId: episode.id,
                            slug: episode.name.slugged,
                            summary: episode.overview,
                            largeBackgroundImage: self.imageURL(episode.stillPath, size: "original"),
                            show: showWithoutEpisodes,
                            episode: episode.episodeNumber,
                            season: episode.seasonNumber,
                            firstAirDate: Self.date(from: episode.airDate)
                        )
                    }
                }
            }
            var result = [Episode]()
            for try await seasonEpisodes in group { result.append(contentsOf: seasonEpisodes) }
            return result.sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        }
        show.episodes = episodes
        return show
    }

    private func request<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var components = URLComponents(string: TMDB.base + path)!
        var parameters = query
        parameters["api_key"] = TMDB.apiKey
        parameters["language"] = "en-US"
        components.queryItems = parameters.map(URLQueryItem.init)
        let (data, response) = try await session.data(from: components.url!)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw CatalogError.unavailable
        }
        return try decoder.decode(T.self, from: data)
    }

    private func imageURL(_ path: String?, size: String) -> String? {
        path.map { "https://image.tmdb.org/t/p/\(size)\($0)" }
    }

    private static func date(from value: String?) -> Date {
        guard let value else { return .distantPast }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value) ?? .distantPast
    }
}

private enum CatalogError: LocalizedError {
    case unavailable, notFound, missingIMDbID

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The catalog provider is temporarily unavailable."
        case .notFound: return "The selected title could not be found in the catalog."
        case .missingIMDbID: return "The selected title does not have an IMDb identifier."
        }
    }
}

private struct CatalogPage: Decodable {
    let results: [CatalogItem]
}

private struct CatalogItem: Decodable {
    let id: Int
    let genreIDs: [Int]

    enum CodingKeys: String, CodingKey { case id; case genreIDs = "genre_ids" }
}

private struct FindResponse: Decodable {
    let movieResults: [CatalogItem]
    let tvResults: [CatalogItem]

    enum CodingKeys: String, CodingKey {
        case movieResults = "movie_results"
        case tvResults = "tv_results"
    }
}

private struct Genre: Decodable { let name: String }
private struct ExternalIDs: Decodable {
    let imdbID: String?
    let tvdbID: Int?
    enum CodingKeys: String, CodingKey { case imdbID = "imdb_id"; case tvdbID = "tvdb_id" }
}
private struct VideoCollection: Decodable { let results: [Video] }
private struct Video: Decodable { let key: String; let site: String; let type: String }

private struct MovieDetail: Decodable {
    let id: Int
    let title: String
    let overview: String
    let releaseDate: String?
    let voteAverage: Double
    let runtime: Int?
    let genres: [Genre]
    let posterPath: String?
    let backdropPath: String?
    let imdbID: String?
    let externalIDs: ExternalIDs?
    let videos: VideoCollection?

    enum CodingKeys: String, CodingKey {
        case id, title, overview, runtime, genres, videos
        case releaseDate = "release_date"; case voteAverage = "vote_average"
        case posterPath = "poster_path"; case backdropPath = "backdrop_path"
        case imdbID = "imdb_id"; case externalIDs = "external_ids"
    }
}

private struct ShowDetail: Decodable {
    struct Season: Decodable {
        let seasonNumber: Int
        enum CodingKeys: String, CodingKey { case seasonNumber = "season_number" }
    }

    let id: Int
    let name: String
    let overview: String
    let firstAirDate: String?
    let voteAverage: Double
    let episodeRunTime: [Int]
    let status: String?
    let genres: [Genre]
    let seasons: [Season]
    let posterPath: String?
    let backdropPath: String?
    let externalIDs: ExternalIDs?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, status, genres, seasons
        case firstAirDate = "first_air_date"; case voteAverage = "vote_average"
        case episodeRunTime = "episode_run_time"; case posterPath = "poster_path"
        case backdropPath = "backdrop_path"; case externalIDs = "external_ids"
    }
}

private struct SeasonDetail: Decodable { let episodes: [EpisodeDetail] }
private struct EpisodeDetail: Decodable {
    let id: Int
    let name: String
    let overview: String
    let episodeNumber: Int
    let seasonNumber: Int
    let airDate: String?
    let stillPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case episodeNumber = "episode_number"; case seasonNumber = "season_number"
        case airDate = "air_date"; case stillPath = "still_path"
    }
}

private extension Popcorn.Genres {
    var tmdbMovieID: Int { tmdbID(isTV: false) }
    var tmdbTVID: Int { tmdbID(isTV: true) }

    func tmdbID(isTV: Bool) -> Int {
        switch self {
        case .action: return isTV ? 10759 : 28
        case .adventure: return isTV ? 10759 : 12
        case .animation: return 16
        case .comedy: return 35
        case .crime: return 80
        case .documentary: return 99
        case .drama: return 18
        case .family: return 10751
        case .fantasy: return isTV ? 10765 : 14
        case .history: return 36
        case .horror: return 27
        case .music: return 10402
        case .mystery: return 9648
        case .thriller: return isTV ? 9648 : 53
        case .war: return isTV ? 10768 : 10752
        case .western: return 37
        case .all: return 0
        }
    }
}
