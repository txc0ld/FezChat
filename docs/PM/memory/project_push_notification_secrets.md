---
name: APNS_ENVIRONMENT secret required on blip-auth
description: Postmortem — all push notifications were silently failing for ~1 week because APNS_ENVIRONMENT secret was never set on the worker. Explains the full failure mode and the required secret set for both workers.
type: project
originSessionId: 23e19cbc-bd0b-4d44-8e1a-8a5f58525300
---
On 2026-04-13 the iOS `aps-environment` entitlement was flipped to `production` (commit `01b8416`) so TestFlight builds would work, but the matching `APNS_ENVIRONMENT` secret was never set on the `blip-auth` Cloudflare worker. Diagnosed and fixed 2026-04-20 during the build 28 TestFlight push.

**The silent-failure chain:**
1. TestFlight issues production APNs device tokens
2. `server/auth/src/apns.ts:14` picks gateway via `env.APNS_ENVIRONMENT === 'production'` → `api.push.apple.com` else `api.sandbox.push.apple.com`
3. Missing secret → falls through to sandbox
4. Apple rejects production tokens against sandbox → `sendPush` catches → returns `false`
5. `handleInternalPush` quietly returns `{sent:0, failed:N}` with 200 OK → no user-visible error, no retry, nothing in app logs

**Fix:** `cd server/auth && echo -n 'production' | npx wrangler secret put APNS_ENVIRONMENT`. Secret-put auto-reloads the isolate, no `wrangler deploy` needed.

**Required secrets (now documented in the respective wrangler.toml files):**

`blip-auth` needs 8 secrets:
- `RESEND_API_KEY`, `DATABASE_URL`, `JWT_SECRET`, `INTERNAL_API_KEY`
- `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_ENVIRONMENT`

`blip-relay` needs 2 secrets:
- `JWT_SECRET` (must match blip-auth)
- `INTERNAL_API_KEY` (must match blip-auth)

**Why:** Three separate teams can touch push (iOS entitlement, APNs certs, worker deploy) and nothing ties them together. A drop-in `wrangler secret put` after a fresh env clone or an account rotation will quietly break push until it's explicitly re-set. The `aps-environment` entitlement MUST match `APNS_ENVIRONMENT` value on the worker — both `production` or both `development`, no exceptions.

**How to apply:** When push notifications are reported broken, FIRST check `cd server/auth && npx wrangler secret list` before anything else. Check both workers. Confirm entitlement matches. Only after that, investigate relay offline-queue behavior, `peer_id_hex` state, or client-side JWT auth.

**Related call-site caching gotcha:** `apns.ts` caches `ApnsClient` at module level in `cachedClient`. If someone mutates `APNS_ENVIRONMENT` again, Cloudflare reloads the isolate automatically on secret change — but if we ever hot-path that value without a `wrangler secret put`, the cache won't refresh.
