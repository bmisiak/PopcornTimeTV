export interface ScrapedItem {
  title: string;
  year?: number;
  score?: number;
}

const EXTRACT_SCHEMA = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string", description: "Movie or show title" },
          year: { type: "integer", description: "Release year if present" },
          score: {
            type: "integer",
            description:
              "Review score shown on the card (Metascore 0-100, Tomatometer 0-100). Omit if absent.",
          },
        },
        required: ["title"],
      },
    },
  },
  required: ["items"],
} as const;

/**
 * Calls Firecrawl's /v1/scrape with the `extract` format to turn a list page
 * into a structured array of titles. Returns [] on failure so the caller can
 * still serve a stale cached result.
 */
export async function firecrawlExtract(
  url: string,
  apiKey: string,
): Promise<ScrapedItem[]> {
  const body = {
    url,
    formats: ["extract"],
    extract: {
      schema: EXTRACT_SCHEMA,
      prompt:
        "Extract every movie/show card on this list page. Return the title, release year if visible, and the numeric review score (Metascore or Tomatometer) shown on the card.",
    },
    onlyMainContent: true,
  };

  const res = await fetch("https://api.firecrawl.dev/v1/scrape", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    console.warn("firecrawl scrape failed", res.status, await res.text());
    return [];
  }

  const json = (await res.json()) as {
    data?: { extract?: { items?: ScrapedItem[] } };
  };
  const items = json.data?.extract?.items ?? [];

  const seen = new Set<string>();
  const deduped: ScrapedItem[] = [];
  for (const item of items) {
    if (!item?.title) continue;
    const key = `${item.title.trim().toLowerCase()}|${item.year ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push({
      title: item.title.trim(),
      year: item.year,
      score: item.score,
    });
  }
  return deduped;
}
