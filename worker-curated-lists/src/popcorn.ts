import type { MediaKind } from "./registry";

/**
 * Probes Popcorn's detail endpoint for an IMDb ID. Returns true if the
 * title is available in the catalog (200 response with a torrent payload).
 *
 * The mapping is cached for 24h — shorter than list resolutions because
 * Popcorn's catalog is volatile (titles get added/removed as torrents churn).
 */
export async function isAvailableOnPopcorn(
  imdbId: string,
  kind: MediaKind,
  popcornBase: string,
  kv: KVNamespace,
): Promise<boolean> {
  const cacheKey = `popcorn:${kind}:${imdbId}`;
  const cached = await kv.get(cacheKey);
  if (cached !== null) return cached === "1";

  const path = kind === "movie" ? "/movie/" : "/show/";
  const url = `${popcornBase.replace(/\/$/, "")}${path}${imdbId}`;
  let available = false;
  try {
    const res = await fetch(url, {
      method: "GET",
      headers: { Accept: "application/json" },
      cf: { cacheEverything: true, cacheTtl: 3600 },
    });
    available = res.ok;
  } catch (err) {
    console.warn("popcorn probe failed", imdbId, err);
  }

  await kv.put(cacheKey, available ? "1" : "0", {
    expirationTtl: 60 * 60 * 24,
  });
  return available;
}
