import type { MediaKind } from "./registry";

/**
 * Resolves a (title, year, kind) to an IMDb ID via OMDb's "find by title"
 * endpoint. Results are cached forever (title+year+kind => imdbId or null)
 * because the mapping never changes. Negative results are cached for 30d
 * in case OMDb temporarily had no hit.
 */
export async function resolveImdbId(
  title: string,
  year: number | undefined,
  kind: MediaKind,
  apiKey: string,
  kv: KVNamespace,
): Promise<string | null> {
  const cacheKey = `imdb:${kind}:${slug(title)}|${year ?? ""}`;
  const cached = await kv.get(cacheKey);
  if (cached !== null) {
    return cached === "__MISS__" ? null : cached;
  }

  const params = new URLSearchParams({
    apikey: apiKey,
    t: title,
    type: kind === "movie" ? "movie" : "series",
    r: "json",
  });
  if (year !== undefined) params.set("y", String(year));

  const res = await fetch(`https://www.omdbapi.com/?${params.toString()}`);
  if (!res.ok) {
    return null;
  }
  const json = (await res.json()) as {
    Response?: string;
    imdbID?: string;
  };

  if (json.Response === "True" && json.imdbID) {
    await kv.put(cacheKey, json.imdbID);
    return json.imdbID;
  }

  await kv.put(cacheKey, "__MISS__", { expirationTtl: 60 * 60 * 24 * 30 });
  return null;
}

function slug(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}
