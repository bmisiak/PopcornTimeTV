export type MediaKind = "movie" | "show";
export type ListSource = "metacritic" | "rottentomatoes";

export interface ListDefinition {
  id: string;
  title: string;
  source: ListSource;
  kind: MediaKind;
  /** URL Firecrawl scrapes. May contain {year} which is expanded to the current year. */
  url: string;
}

/**
 * Default registry seeded at first run. Consumers (the app) read this through
 * `GET /lists` which merges the default set with any overrides stored in KV
 * under `registry:overrides`.
 *
 * Adding a new list = appending an entry here (or pushing to the KV override).
 * No app release required — the iOS/tvOS client pulls the registry on launch.
 */
export const DEFAULT_REGISTRY: ListDefinition[] = [
  {
    id: "metacritic-movies-current-year",
    title: "Metacritic \u2014 Movies {year}",
    source: "metacritic",
    kind: "movie",
    url: "https://www.metacritic.com/browse/movie/all/all/current-year/",
  },
  {
    id: "metacritic-shows-current-year",
    title: "Metacritic \u2014 TV {year}",
    source: "metacritic",
    kind: "show",
    url: "https://www.metacritic.com/browse/tv/all/all/current-year/",
  },
  {
    id: "rottentomatoes-movies-current-year",
    title: "Rotten Tomatoes \u2014 Movies {year}",
    source: "rottentomatoes",
    kind: "movie",
    url: "https://www.rottentomatoes.com/browse/movies_at_home/sort:popular",
  },
  {
    id: "rottentomatoes-shows-current-year",
    title: "Rotten Tomatoes \u2014 TV {year}",
    source: "rottentomatoes",
    kind: "show",
    url: "https://www.rottentomatoes.com/browse/tv_series_browse/sort:popular",
  },
];

export function expandTitle(def: ListDefinition): string {
  const year = new Date().getUTCFullYear();
  return def.title.replace("{year}", String(year));
}
