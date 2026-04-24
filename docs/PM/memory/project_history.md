---
name: Project current state and active work
description: Current repo state, open backlog, pending verifications. For pre-2026-04-22 detail see project_history_archive.md.
type: project
originSessionId: 6e15e31b-7115-4971-bf13-07d171f32b25
---
## Current state (as of 2026-04-24 morning AWST)

### TestFlight
- **Build 29** (`alpha-1.0.0-29` at commit `537100d`) deployed via GitHub Actions workflow `24713328183` — **completed: success** (08:54→09:03 UTC 2026-04-21). Carries PRs #250–#254 (relay foreground state, BLE Debug WS indicator, signed manifests, auth refresh grace, docs fix).
- Build 28 (tag `alpha-1.0.0-28`, commit `fc1ffcc`, PR #235) was the prior live build.
- Verification still owed: confirm users have actually picked up build 29.

### Repo (fully cleaned 2026-04-24)
- Local checkout: `~/heyblip/` (NOT `~/FezChat/`). Repo: `txc0ld/heyblip`.
- Local `~/FezChat/` is John's Finder-facing folder — handoff markdown and plugin bundle live here.
- **Origin is `main`-only.** PR #246 closed (work tracked by HEY-1283 for later), `refactor/HEY-1283-notification-recovery-extraction` branch deleted. 30 other stale remote branches deleted on 2026-04-24.
- **Local Mac fully clean.** John ran the cleanup one-liner: 31 stale origin tracking refs pruned, 39 worktrees pruned (only `~/heyblip` main checkout remains), all local branches except `main` deleted, external worktree dirs (`~/FezChat-*`, `~/heyblip-*`, `~/worktrees`, `~/heyblip/.claude/worktrees`) all removed. Bonus: cleared three batches of stale `.git/*.lock` files left by an earlier crashed git process (verified no live git processes were holding them).

### Workers (live as of 2026-04-24)
- `blip-auth.john-mckean.workers.dev` — reachable, JWT auth + email verification + Ed25519 challenge-response live.
- `blip-relay.john-mckean.workers.dev` — reachable (WS endpoint).
- `blip-cdn.john-mckean.workers.dev` — version `dfe703bd-b8a9-49f5-b2e3-c74c1dc9a6d2`, manifest signed (Ed25519), 6 events served. Verified `/manifests/events.json` returns 200 with valid signature field.
- All three deployed with `SENTRY_DSN` (PR #249). `MANIFEST_SIGNING_KEY` set on blip-cdn.

---

## Notion takeover — 2026-04-24 EOD

Issue tracker flipped from Bugasura to Notion. HeyBlip workspace at https://www.notion.so/HeyBlip-34c3e435f07a80acbe11e76655af9ebf. Tasks DB id `34c3e435-f07a-8175-bbdd-e0c455d106f7`. HEY-N IDs continue from the Bugasura import (next available: HEY-1334). Bugasura at my.bugasura.io/HeyBlip is read-only archive. Cowork has the Notion personal token (`ntn_167…`) — see `reference_notion_workspace.md` for canonical patterns. Hub page now has 🤖 callout pointing to a "Fresh agent orientation" sub-page (paste-as-prompt template). All in-repo docs (CLAUDE.md, TAY-DISPATCH-PROMPT.md, slack-bot/tay-onboarding-prompt.md) and memory files (operating_model, slack_rules, prompt_rules, feedback_*, MEMORY index) updated to point at Notion. **Tracking ticket:** HEY-1332 (sync direction lock-down + Slack auto-post replacement) — still open, will land tomorrow.

## Bugasura — current backlog (after 2026-04-24 transitions, mirrored to Notion)

### Closed today (2026-04-24)
| HEY | Status | Resolution |
|---|---|---|
| HEY1304 | Fixed | PR #253 (8e2e683) |
| HEY1305 | Fixed | PR #251 (d46b10e) |
| HEY1306 | Fixed | PR #252 + CDN deploy `dfe703bd` |
| HEY1307 | Fixed | PR #250 (92239a0) |
| HEY1308 | Fixed | PR #254 (537100d) |
| HEY1309 | Closed | Endpoint not actually broken — needs all 4 params (see reference_bugasura_api.md) |

### Open backlog — Linear Import sprint (152746)
| HEY | Sev / Type | Title |
|---|---|---|
| **HEY1315** | **MEDIUM / FEATURE** | **`[RELAY] Wake + drain relay via silent push (content-available: 1)`** — biggest UX win on the board |
| **HEY1318** | **MEDIUM / BUG** | `[RELAY] Foreground resume triggers 3+ WebSocket reconnect cycles in 1.5s` — fix scoped in ticket |
| HEY1310 | LOW / TECH-DEBT | `[RELAY] Collapse WebSocketTransport.openWebSocket teardown into a single critical section` |
| HEY1311 | LOW / TECH-DEBT | `[RELAY] Convert WebSocketTransport from @unchecked Sendable + NSLock to actor` |
| HEY1312 | LOW | Stale-local-main process fix (require `git fetch && checkout origin/main` pre-flight) |
| HEY1313 | LOW / TECH-DEBT | `[OPS] node-script-pipe-to-wrangler-secret-put is unsafe — wrap in stderr-gated helper` |
| HEY1314 | LOW / TECH-DEBT | `[RELAY] Explicit relay stop on scenePhase == .background` |
| HEY1316 | LOW / FEATURE | `[RELAY] Add BGProcessingTaskRequest to complement 15-min BGAppRefreshTask floor` |
| HEY1317 | LOW / FEATURE | `[RELAY] Background URLSessionConfiguration to drain queued packets while suspended` |
| HEY1319 | LOW | Foreground reconnect log cosmetic |

### Open backlog — Audit Gaps sprint (153022)
6 still open: HEY1245 (ad-hoc events), HEY1250 (saved-items out-of-range), HEY1252 (breadcrumb trails), HEY1260 (design spec email-auth update), HEY1277 (typography 12 roles), HEY1280 (manifest-signing follow-up — likely already addressed by HEY1306).

### Older In Progress (carried over)
- **HEY1192** — PUSH-5 smoke test (HIGH)
- **HEY1187** — Push notifications + reliable delivery epic (HIGH)
- **HEY1178** — `[WEB]` Fix false claims in Security section + Pricing copy (MEDIUM)

### Older context still live
- **HEY1288** — Sentry Releases: scope-tag → native migration
- **HEY1289** — pre-existing 401 cascade, back-button-nav angle. Watch if APPLE-IOS-1 persists post-build-29

---

## Open PRs (1)

- **PR #246** — `refactor: extract notification routing and registration recovery from AppCoordinator`
  - Branch: `refactor/HEY-1283-notification-recovery-extraction` (6b08867)
  - Status: **draft**, mergeable_state: clean, +569/-185 across 5 files, ticket HEY1283
  - Author: iamjohnnymac (John), opened 2026-04-20T13:14, untouched since
  - Decision pending: ship-or-scrap. This is the next step in the AppCoordinator decomposition (after HEY1282/PR #245). Real refactor work — not stale code, just stalled.

---

## Outstanding for John

1. **Decide PR #246** — merge (it's clean), close (track via HEY1283 to redo), or mark Ready for Review and let the reviewer process pick it up.
2. **Verify build 29 distribution** via TestFlight Connect dashboard.
3. **Verify APPLE-IOS-1 Sentry issue trending dark** (was 163 events / 29 users at build 28 EOD). Once dark, mark as "Resolved in next release". Also resolve `APPLE-IOS-6, -1T, -1V, -1W, -1X` (pre-#248 test-harness ghosts).
4. **Local repo cleanup** on Mac (one-liner above) to drop the ~50 worktree refs + ~65 local branches.
5. **Bugasura MCP plugin** — `~/FezChat/heyblip-team.plugin` waiting for double-click. Future PM sessions get proper MCP tools instead of curl.
6. **Pick next dispatch from backlog.** Recommended order: HEY1315 (silent push relay wake), then HEY1318 (foreground reconnect race).

See `operating_model.md` for dispatch/merge/reviewer rules and `tooling_gotchas.md` for lessons learned.
