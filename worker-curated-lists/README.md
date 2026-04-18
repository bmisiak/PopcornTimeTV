# popcorn-curated-lists

Cloudflare Worker that builds curated movie / show lists from Metacritic and
Rotten Tomatoes, then filters them down to titles that are actually available
on the PopcornTime catalog. The iOS / tvOS / macOS app consumes the result
through `CuratedListsApi` in `PopcornKit`.

## Pipeline

```
┌────────────┐   scrape    ┌──────────┐   resolve   ┌──────┐   probe   ┌─────────┐
│ Firecrawl  │ ─────────▶  │ title +  │ ─────────▶  │ OMDb │ ────────▶ │ Popcorn │
│ /v1/scrape │             │  year    │             │  API │           │  /movie │
└────────────┘             └──────────┘             └──────┘           └─────────┘
                                                                            │
                                                                            ▼
                                                                        Cloudflare KV
                                                                   (list:<id>, imdb:<…>,
                                                                    popcorn:<…>)
```

Each step is cached:

- **list results** → 7 days (refreshed weekly by cron)
- **title → IMDb ID** → forever (negative lookups 30 days)
- **IMDb ID → PopcornTime availability** → 24 hours (catalog churns)

## Endpoints

| Method | Path                     | Notes                                             |
| ------ | ------------------------ | ------------------------------------------------- |
| GET    | `/lists`                 | Returns the list registry (default + KV overrides).|
| GET    | `/lists/:id`             | Returns a cached, enriched `{ items: [{ imdbId }] }`.|
| POST   | `/admin/refresh?id=<id>` | Forces refresh. Requires `Authorization: Bearer ADMIN_TOKEN`.|

## Cost (Firecrawl)

4 lists × weekly = **~16 scrapes/month**. Each `/scrape` with `extract` is
≈ 5 credits → **~80 credits/month**, inside Firecrawl's free tier
(500 credits/mo). Well under the cheapest paid plan if we outgrow it.

## Secrets

```
wrangler secret put FIRECRAWL_API_KEY
wrangler secret put OMDB_API_KEY
wrangler secret put ADMIN_TOKEN
```

Set `POPCORN_BASE` in `wrangler.toml` (or override via a secret) to whichever
mirror is currently live. The worker does not dynamically resolve Popcorn
mirrors — if one goes down, just redeploy with a new `POPCORN_BASE`.

## Setup

```bash
cd worker-curated-lists
npm install
wrangler kv:namespace create CURATED_CACHE
# copy the returned id into wrangler.toml -> kv_namespaces.id
wrangler secret put FIRECRAWL_API_KEY
wrangler secret put OMDB_API_KEY
wrangler secret put ADMIN_TOKEN
npm run deploy
```

After the first deploy, warm the cache manually:

```bash
curl -X POST "https://<your-worker>.workers.dev/admin/refresh?id=metacritic-movies-current-year" \
     -H "Authorization: Bearer $ADMIN_TOKEN"
```

Subsequent refreshes run from the cron trigger defined in `wrangler.toml`
(Mondays at 03:00 UTC).

## Adding a new list

Two options — both require zero app releases:

1. **Compile-time** (preferred): append an entry to `DEFAULT_REGISTRY` in
   `src/registry.ts` and redeploy.
2. **Runtime override**: `PUT` a JSON array of `ListDefinition` into KV under
   the key `registry:overrides`. The worker merges it over the defaults on
   every `GET /lists`.

## Next steps — app-side wiring

The Swift client is already in place:

- `PopcornKit/Sources/Managers/CuratedListsApi.swift`
- `PopcornKit/Sources/Models/CuratedList.swift`
- `CuratedLists.base` in `PopcornKit/Sources/Managers/NetworkConfigurations.swift`

To finish the UX, add a `CuratedListsView` to the `PopcornTime` target:

1. New file `PopcornTime/Flows/Curated/CuratedListsView.swift` rendering one
   `LazyVStack` section per list (title + horizontal `ScrollView` of
   `MovieView` / `ShowView`).
2. A `CuratedListsViewModel` that calls
   `CuratedListsApi.shared.loadRegistry()` on appear, then fans out
   `loadList(id:)` + `hydrateMovies(_:)` / `hydrateShows(_:)` per entry.
3. Either register the view as a new `TabBarView.Selection.curated` tab
   (remember the macOS counterpart in `MacTabBarView.swift`) or surface it as
   a header strip at the top of the existing `MoviesView` / `ShowsView`.
4. Both require adding the new `.swift` files to `PopcornTime.xcodeproj` —
   easiest to do interactively in Xcode ("Add Files to PopcornTime…") so the
   target memberships and build phases get updated correctly.
