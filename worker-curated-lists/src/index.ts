import { readList, writeList } from "./cache";
import { firecrawlExtract } from "./firecrawl";
import { isAvailableOnPopcorn } from "./popcorn";
import {
  DEFAULT_REGISTRY,
  expandTitle,
  type ListDefinition,
} from "./registry";
import { resolveImdbId } from "./resolver";

export interface Env {
  CURATED_CACHE: KVNamespace;
  FIRECRAWL_API_KEY: string;
  OMDB_API_KEY: string;
  ADMIN_TOKEN: string;
  POPCORN_BASE: string;
}

export interface EnrichedItem {
  imdbId: string;
  title: string;
  year?: number;
  score?: number;
}

export interface EnrichedList {
  id: string;
  title: string;
  source: string;
  kind: "movie" | "show";
  updatedAt: string;
  items: EnrichedItem[];
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext) {
    const url = new URL(request.url);

    // Public read endpoints
    if (request.method === "GET" && url.pathname === "/lists") {
      return json(await loadRegistry(env));
    }
    const listMatch = url.pathname.match(/^\/lists\/([^/]+)$/);
    if (request.method === "GET" && listMatch) {
      const id = decodeURIComponent(listMatch[1]);
      const list = await readList(id, env.CURATED_CACHE);
      if (!list) return notFound(`list '${id}' not yet generated`);
      return json(list);
    }

    // Admin: force refresh a single list. Protects KV writes via token.
    if (
      request.method === "POST" &&
      url.pathname === "/admin/refresh" &&
      authorized(request, env)
    ) {
      const id = url.searchParams.get("id");
      if (!id) return badRequest("missing ?id=<listId>");
      const registry = await loadRegistry(env);
      const def = registry.find((d) => d.id === id);
      if (!def) return notFound(`unknown list '${id}'`);
      const list = await refreshOne(def, env);
      return json(list);
    }

    if (request.method === "GET" && url.pathname === "/") {
      return json({
        service: "popcorn-curated-lists",
        endpoints: ["GET /lists", "GET /lists/:id"],
      });
    }

    return notFound("unknown route");
  },

  // Weekly cron: refresh every list in the registry, sequentially so we stay
  // well under Firecrawl/OMDb rate limits. Failures for one list don't block
  // the others.
  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(refreshAll(env));
  },
};

async function loadRegistry(env: Env): Promise<ListDefinition[]> {
  const overridesRaw = await env.CURATED_CACHE.get("registry:overrides");
  const overrides: ListDefinition[] = overridesRaw
    ? (JSON.parse(overridesRaw) as ListDefinition[])
    : [];
  const byId = new Map<string, ListDefinition>();
  for (const def of DEFAULT_REGISTRY) byId.set(def.id, def);
  for (const def of overrides) byId.set(def.id, def);
  return [...byId.values()].map((def) => ({ ...def, title: expandTitle(def) }));
}

async function refreshAll(env: Env): Promise<void> {
  const registry = await loadRegistry(env);
  for (const def of registry) {
    try {
      await refreshOne(def, env);
    } catch (err) {
      console.error("refresh failed", def.id, err);
    }
  }
}

async function refreshOne(
  def: ListDefinition,
  env: Env,
): Promise<EnrichedList> {
  const scraped = await firecrawlExtract(def.url, env.FIRECRAWL_API_KEY);

  const enriched: EnrichedItem[] = [];
  for (const item of scraped) {
    const imdbId = await resolveImdbId(
      item.title,
      item.year,
      def.kind,
      env.OMDB_API_KEY,
      env.CURATED_CACHE,
    );
    if (!imdbId) continue;

    const available = await isAvailableOnPopcorn(
      imdbId,
      def.kind,
      env.POPCORN_BASE,
      env.CURATED_CACHE,
    );
    if (!available) continue;

    enriched.push({
      imdbId,
      title: item.title,
      year: item.year,
      score: item.score,
    });
  }

  const list: EnrichedList = {
    id: def.id,
    title: expandTitle(def),
    source: def.source,
    kind: def.kind,
    updatedAt: new Date().toISOString(),
    items: enriched,
  };
  await writeList(list, env.CURATED_CACHE);
  return list;
}

function authorized(request: Request, env: Env): boolean {
  const header = request.headers.get("Authorization") ?? "";
  const expected = `Bearer ${env.ADMIN_TOKEN}`;
  return env.ADMIN_TOKEN.length > 0 && header === expected;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=300",
    },
  });
}

function notFound(message: string): Response {
  return json({ error: message }, 404);
}

function badRequest(message: string): Response {
  return json({ error: message }, 400);
}
