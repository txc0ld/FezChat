# blip-cdn

Cloudflare Worker at `blip-cdn.john-mckean.workers.dev`. Serves avatars (R2),
static manifests, and the **events manifest** backed by Neon Postgres.

## Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| `POST` | `/avatars/upload` | User JWT | multipart/form-data JPEG upload |
| `GET` | `/avatars/:id.jpg` | public | R2 passthrough |
| `GET` | `/manifests/events.json` | public | DB-backed, cached 1h at the edge |
| `GET` | `/manifests/*` | public | R2 passthrough for other manifests |
| `GET` | `/v1/events` | `INTERNAL_API_KEY` | admin list |
| `POST` | `/v1/events` | `INTERNAL_API_KEY` | admin create |
| `PUT` | `/v1/events/:id` | `INTERNAL_API_KEY` | admin update |
| `DELETE` | `/v1/events/:id` | `INTERNAL_API_KEY` | admin delete |
| `GET` | `/health` | public | liveness |

The response shape of `GET /manifests/events.json` is the `EventManifest`
struct iOS decodes in `EventsViewModel` (`version`, `signature`, `events[]`).

## One-time setup

```bash
# Install deps
npm ci

# Set secrets (reuse the same values the other workers use)
wrangler secret put JWT_SECRET
wrangler secret put DATABASE_URL
wrangler secret put INTERNAL_API_KEY

# Apply schema + seed against the Neon DB
psql "$DATABASE_URL" -f schema.sql
psql "$DATABASE_URL" -f seed.sql

# Deploy
npm run deploy
```

## Adding events

Admin writes are gated by `INTERNAL_API_KEY`. There's no admin UI — this is a
curl workflow. New events are visible to clients within the 1-hour CDN cache
TTL (sooner for anyone whose edge cache has expired).

```bash
export BASE=https://blip-cdn.john-mckean.workers.dev
export KEY=<your INTERNAL_API_KEY>

# Create
curl -X POST "$BASE/v1/events" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Falls Festival",
    "latitude": -38.5167,
    "longitude": 145.9833,
    "radiusMeters": 2000,
    "startDate": "2026-12-30T00:00:00Z",
    "endDate": "2027-01-01T23:59:59Z",
    "location": "Lorne, VIC",
    "description": "Three-day festival on the Great Ocean Road.",
    "attendeeCount": 16000,
    "category": "festival"
  }'

# List
curl -H "Authorization: Bearer $KEY" "$BASE/v1/events"

# Update (full replace — send all required fields)
curl -X PUT "$BASE/v1/events/<uuid>" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{ ... same shape as create ... }'

# Delete
curl -X DELETE "$BASE/v1/events/<uuid>" \
  -H "Authorization: Bearer $KEY"

# Public manifest (what iOS fetches)
curl "$BASE/manifests/events.json"
```

### Allowed categories

`festival`, `sport`, `marathon`, `concert`, `other`. Anything else is
rejected with a 400; the iOS `EventsViewModel.eventCategory(for:)` maps
unknown values to `.other`.

### Validation

- `name`, `latitude`, `longitude`, `radiusMeters`, `startDate`, `endDate` are required.
- `latitude` ∈ [-90, 90], `longitude` ∈ [-180, 180], `radiusMeters` > 0.
- `startDate` and `endDate` must be ISO 8601; `endDate` ≥ `startDate`.
- `attendeeCount` must be a non-negative integer if provided.

## Tests

```bash
npm test
```

Uses `vitest` + `@cloudflare/vitest-pool-workers`. The Neon client is mocked;
no live DB is needed.
