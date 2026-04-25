---
name: Project current state and active work
description: Current repo state, open backlog, pending verifications. For pre-2026-04-22 detail see project_history_archive.md.
type: project
---

> **Issue tracker note (2026-04-25):** All HEY-N references below are pre-migration Bugasura/Notion IDs. They were imported into Jira BDEV with new BDEV-N numbers but their original HEY-N is preserved on each ticket as the `HEY ID` custom field. To find the new BDEV equivalent: `JQL: "HEY ID" = "HEY-1334"`. New tickets file directly in Jira BDEV (no HEY prefix — just BDEV-N).

## Current state (as of 2026-04-25 ~19:30 AWST — claude-pm-1 orientation)

### Headline
**Build 43 built + uploaded successfully** (workflow run `24926469648` = `success`). Build 43 carries everything in build 42 plus the four post-smoke-test fixes:
- BDEV-368 / PR #266 — Workers Service Bindings (auth↔relay) → fixes CF error 1042 push pipeline
- BDEV-369 / PR #267 — onboarding chains mic permission after BLE
- BDEV-370 / PR #268 — fragment >MTU addressed packets (images + voice notes)
- HEY-1318 / PR #256 — relay coalesce concurrent reconnect triggers
- HEY-1323 / PR #265 — chat UX (reactions on wire, friend count, reply integrity)

App Store Connect processing is John's manual confirmation — not yet done from session.

### Earlier today (push-notifications session, 2026-04-25 ~05:38 UTC)
HEY-1321 production push notifications shipped via PR #264 → squash-merged as `00439c5`, then SOUL.md follow-up at `03de535`. TestFlight build **1.0.0 (42)** uploaded via deploy-testflight.yml run `24923695627` after **11 deploy attempts** — every failure was a real, separable issue. Trail in the merge commit body and the workflow runs.

### TestFlight
- **Build 43** (`beta-1.0.0-43` at commit `6614568`) — workflow `24926469648` completed `success` at 2026-04-25 ~08:11 UTC. Includes all post-smoke-test fixes. Apple processing not yet confirmed.
- **Build 42** (`beta-1.0.0-42` at commit `f3a9912` of the PR branch — squashed onto main as `00439c5`) on TestFlight as of 2026-04-25 ~05:38 UTC. Build 42 already picks up the BDEV-368/372 worker-side fixes (auth↔relay Service Binding + INTERNAL_API_KEY rotation) automatically — no rebuild required for those. Build 43 adds the iOS-side BDEV-369 (mic) + BDEV-370 (fragmentation) fixes.
- Builds 30/31 still installable for legacy QA — they don't have NSE or new endpoints but are backwards-compat with the new auth/relay code (verified routes match).

### Workers (live)
- `blip-auth.john-mckean.workers.dev` — version `61a29aff` (deployed 2026-04-25 ~07:33 UTC after BDEV-368 Service Binding rewire). Service Binding `RELAY = blip-relay`. `INTERNAL_API_KEY` rotated to fresh 64-hex-char token (matches relay). Endpoints `/v1/users/notification-prefs` and `/v1/badge/clear` live, plus the legacy routes. Push secrets: `APNS_BUNDLE_ID_PROD`, `APNS_BUNDLE_ID_DEBUG`.
- `blip-relay.john-mckean.workers.dev` — version `4c6e3ae3` (deployed 2026-04-25 ~07:32 UTC). Service Binding `AUTH = blip-auth`. `MAX_QUEUED_PER_PEER` bumped 50 → 1000 for fragmented-image bursts. `INTERNAL_API_KEY` matches auth. Triggers push when recipient is offline.
- `blip-cdn.john-mckean.workers.dev` — unchanged.

**Verified end-to-end this session:** `POST /v1/badge/clear → HTTP 200 {"cleared":true,"badgeCount":0}`. Auth → Service Binding → Relay → DO chain confirmed working. **CF error 1042 is gone.**

### Neon (live)
- Migration `002_push_notifications.sql` applied 2026-04-25 ~04:21 UTC. Additive, idempotent: `device_tokens` gained `locale`, `app_version`, `sandbox`, `last_registered_at`; new `notification_prefs` table.
- DATABASE_URL connection string is in the older `~/Documents/Vibe Coding/FezChat/FezChat/blip-memory-export/.env` (not in `~/heyblip/.claude/skills/secrets/.env`). Worth pulling into the canonical secrets file at next rotation.

### Repo
- `origin/main` at `6614568` (after #256 + #265 + #266 + #267 + #268 all merged today).
- John's local `~/heyblip` is on `main` at `6c21508` — his own docs commit on top of `c954ec5` (the BDEV-370 merge), so local has diverged from origin: 1 commit local-only, 2 commits remote-only. **Don't `git pull`** — let John reconcile his own docs branch.
- Earlier session worktrees (`heyblip-workers-service-bindings`, `heyblip-mic-permission`, `heyblip-relay-frag`, `heyblip-HEY-1318`) all cleaned up. None left around.
- Self-hosted runner `johns-mac` (PID 82202 on the Air, registered to `iamjohnnymac/xfit365-ios`) is running but not connected to heyblip. Future option if GitHub-hosted runners keep being unstable.

### Apple Developer Portal
- 4 App IDs: `au.heyblip.Blip`, `.debug`, `.notifications`, `.debug.notifications`. All linked to App Group `group.com.heyblip.shared`. Push enabled on the two main IDs.
- 3 fresh provisioning profiles regenerated 2026-04-25: `Blip App Store Distribution`, `Blip NSE Distribution`, `Blip Debug NSE Distribution`. All Active, expire 2027-04-12.
- APNs auth key reused: kid `97V5K3RVF3` (Team Scoped, Sandbox & Production), `.p8` at `~/Downloads/AuthKey_97V5K3RVF3.p8`.
- Two stray `.p8` files in Downloads (`AuthKey_U592D5NB99.p8`, `AuthKey_8L72H5H8CD.p8`) likely from xfit365ios — soft hygiene cleanup someday.

### CI infrastructure (the 11-attempt saga)
The `deploy-testflight.yml` workflow now handles the NSE target cleanly. Key takeaways for the next PM that has to debug it:
- **Xcode picker is hardcoded** to a preference list of GitHub-documented stable Xcode 26.x versions (26.4.1 → 26.0.1). Do NOT switch back to a discovery walk — the macos-26 image has undocumented sibling dirs (`Xcode_26.5.0.app`, `Xcode_26.5.app`, `Xcode_26.4.app`, etc.) that are partial installs whose iOS platform is missing. They fool every probe except actual archive.
- **Manual signing is pinned per-target in `project.yml`** (Release config only — Debug stays Automatic for local dev). xcodebuild's CLI doesn't expose per-target `PROVISIONING_PROFILE_SPECIFIER` overrides, and Automatic signing on CI fails ("No Accounts") because runners have no logged-in Apple ID.
- **Two profiles imported, not one** — `PROVISIONING_PROFILE` (main) + `PROVISIONING_PROFILE_NSE` (extension). Both wired via base64-decoded GitHub Actions secrets. ExportOptions.plist maps both bundle IDs.
- **App icons must be alpha-stripped** for App Store. The PR's original 3-image "single-size + appearances" set produced PNGs with alpha that the asset compiler rejected. Replaced with a full pre-rendered set (19 PNGs covering all iOS sizes + 1024×1024 marketing icon, all 8-bit RGB no alpha).

---

## Jira BDEV state (post-session, 2026-04-25 ~19:30 AWST)

**54 open tickets** in BDEV (statusCategory != Done). Full list is in Jira; highlights below. **DO NOT transition status from engineer-agent role — Cowork (PM) owns workflow.**

### Closed this session via PM transitions (claude-pm-1, ~20:03 AWST)

PM transitioned the four merged-but-still-To-Do tickets to Done with PR-link comments:

| Ticket | PR | Closed | Note |
|---|---|---|---|
| [BDEV-368](https://heyblip.atlassian.net/browse/BDEV-368) | #266 → `042d46f` | ✅ Done | Workers Service Bindings (CF 1042 fix), both workers redeployed |
| [BDEV-369](https://heyblip.atlassian.net/browse/BDEV-369) | #267 → `6356ac7` | ✅ Done | Mic permission chain in onboarding, in build 43 |
| [BDEV-370](https://heyblip.atlassian.net/browse/BDEV-370) | #268 → `c954ec5` | ✅ Done | >MTU fragmentation for images + voice, in build 43 |
| [BDEV-372](https://heyblip.atlassian.net/browse/BDEV-372) | (no PR — secret rotation) | ✅ Done | INTERNAL_API_KEY rotated, end-to-end verified |

**Atlassian MCP attribution caveat:** comments posted via the MCP authenticate as the OAuth user (John). All PM-posted comments are signed `— claude-pm-1` in the body so the agent attribution is preserved in the audit trail.

PRs #265 (HEY-1323 chat UX) and #256 (HEY-1318 reconnect race) are also merged on origin/main; their Jira equivalents need looking up via JQL `"HEY ID" = "HEY-1323"` / `"HEY ID" = "HEY-1318"` and may need similar transitions.

### High-priority tickets still open

- [BDEV-373](https://heyblip.atlassian.net/browse/BDEV-373) (Highest, To Do) — **Noise XX retry rotates initiator ephemeral, relay-buffered msg2 fails decryption, DMs queue forever**. Filed 2026-04-25 19:18.
- [BDEV-371](https://heyblip.atlassian.net/browse/BDEV-371) (High, To Do) — BLE peerID mismatch when contact's noise key rotates. Two-device repro logs in ticket. Re-test on fresh build 43 install before deciding stale-state vs real bug.
- [BDEV-260](https://heyblip.atlassian.net/browse/BDEV-260) (High, In Progress) — PUSH-5 deploy + smoke test. Becomes runnable now build 43 is up.
- [BDEV-355](https://heyblip.atlassian.net/browse/BDEV-355) (High, In Progress) — production push notifications iOS+Workers+APNs (parent of HEY-1321 work).
- [BDEV-374](https://heyblip.atlassian.net/browse/BDEV-374) / [BDEV-375](https://heyblip.atlassian.net/browse/BDEV-375) / [BDEV-376](https://heyblip.atlassian.net/browse/BDEV-376) — handshake testing tickets (two-phone harness, chaos coverage, soak test). Filed 19:18.
- [BDEV-377](https://heyblip.atlassian.net/browse/BDEV-377) — handshake state-machine telemetry. Filed 19:18.
- [BDEV-378](https://heyblip.atlassian.net/browse/BDEV-378) — process: add "Verified on devices" gate between Merged and Done. Filed 19:18.

### Launch-prep stack (8 tickets, blocks App Store submission)

[BDEV-359](https://heyblip.atlassian.net/browse/BDEV-359), [BDEV-360](https://heyblip.atlassian.net/browse/BDEV-360), [BDEV-361](https://heyblip.atlassian.net/browse/BDEV-361), [BDEV-362](https://heyblip.atlassian.net/browse/BDEV-362), [BDEV-363](https://heyblip.atlassian.net/browse/BDEV-363), [BDEV-364](https://heyblip.atlassian.net/browse/BDEV-364), [BDEV-365](https://heyblip.atlassian.net/browse/BDEV-365), [BDEV-366](https://heyblip.atlassian.net/browse/BDEV-366) — App Store Connect manual work (Info.plist purpose strings audit, anonymous-chat defence write-up, moderation policy, debug overlay gating, /support page on heyblip.au, screenshots, privacy nutrition label, reviewer demo account).

### Closed during this session window (2026-04-25)

Earlier (push-notifications session): HEY-1321 fixed (PR #264 → `00439c5`). HEY-1331 cancelled (misdiagnosis).

Smoke-test debrief session: BDEV-368/369/370 shipped via PRs #266/267/268, BDEV-372 resolved (INTERNAL_API_KEY rotation).

Late evening (post-handover, 18:46–19:18): BDEV-29, BDEV-184, BDEV-235, BDEV-315, BDEV-318, BDEV-319 all transitioned to Done.

---

## Open PRs

**Zero.** All five PRs from start of session merged: #266, #267, #268 (all mine, BDEV-368/369/370), #265 (Tay's, HEY-1323), #256 (John's, HEY-1318).

---

## Atlassian MCP

Added at user scope this session via `claude mcp add --scope user --transport sse atlassian https://mcp.atlassian.com/v1/sse`. John then re-added via the Claude Code App connector UI (CLI version was removed first to avoid duplicate-URL collision). Once OAuth-authenticated, `mcp__atlassian__*` tools should resolve. Until then, Jira/Confluence access is via REST + `JIRA_API_TOKEN` from `~/heyblip/.claude/skills/secrets/.env`.

Bugasura MCP entry was removed this session (Bugasura is a read-only archive — cross-tracker noise).

---

## Owed to John (manual, non-dispatchable)

1. **§5 push smoke test** on real device — install build 42 OR build 43 once processed → background app → ping me, I tail `wrangler tail blip-auth` and we fire the curl from `docs/OPS_APNS.md` §5. Want `push.attempted` then `push.success` with `apnsStatus=200` in the structured logs.
2. **HEY-1192 / PUSH-5 two-phone test** — verify cross-device convergence, especially the silent_badge_sync fan-out which we never end-to-end exercised.
3. **TestFlight build 43 processing confirmation** — refresh App Store Connect → HeyBlip → TestFlight and verify build 43 is past Processing.
4. **BDEV-371 BLE peerID mismatch re-test** — fresh install of build 43 with both Fabs's and John's phone wiped, before deciding stale state vs real key-rotation handling bug.
5. **Sentry housekeeping** — APPLE-IOS-1, -1T, -1V, -1W, -1X, -6 still need "Resolved in next release" clicks. Same items from prior sessions.
6. **Bugasura → Slack webhook off** — stop the cross-tracker noise into #blip-dev (Bugasura is archive only).

---

## What the next PM should know on day-one

1. **Read SOUL.md first.** It's now wired into HANDOVER.md and PM-ORIENTATION-PROMPT.md as step 3 / first item. Don't skip it.
2. **The CI pipeline is fragile but documented.** If `deploy-testflight.yml` starts failing, read this file's "CI infrastructure" section + the project_history_archive.md "11-attempt saga" notes before debugging.
3. **PRs #266/267/268 are MERGED but Jira tickets BDEV-368/369/370/372 still show "To Do".** First action: verify on main, then transition to Done.
4. **Workers cross-Worker calls require Service Bindings**, not public-URL fetch. CF returns `error code: 1042` for workers.dev → workers.dev fetch on the same account. Both directions auth↔relay are now bound; if you add a new cross-Worker call, repeat the pattern.
5. **`INTERNAL_API_KEY` must match across blip-auth and blip-relay.** Shared secret. If badge clear or push internally returns 401, that's the first thing to check.
6. **Atlassian API gotchas:** rate limits look like 401/404 (not 429), pace ≥1s between calls. Use the plain "Create API token" button, NOT "Create with scopes" (scoped tokens default read-only and break writes).
7. **Don't transition Jira tickets from engineer-agent role.** PM/Cowork owns workflow. Engineer-agent allowed writes: `Assignee` → self when claiming, comment with PR URL, paste PR URL into description.
8. **Don't merge own PRs by default** — John merges via PAT. Per-instance authorization (e.g., "merge it") may be given explicitly; match the scope precisely. (PM/Cowork has separate merge authority per `operating_model.md`.)
9. **Self-hosted runner option exists** if GitHub-hosted runners go bad again. The `johns-mac` listener on the Air is registered to xfit365ios but a second instance pointed at heyblip would take ~10 min to set up and would dodge image-rotation surprises.

---

## Credentials

All in `~/heyblip/.claude/skills/secrets/.env`:
- `JIRA_EMAIL`, `JIRA_API_TOKEN`, `JIRA_BASE_URL` — Jira REST API (note: HANDOVER.md calls this `ATLASSIAN_TOKEN`; same thing, env var name is `JIRA_API_TOKEN`)
- `GITHUB_PAT` — `gh` CLI (use as `GITHUB_TOKEN=$GITHUB_PAT`)
- `SLACK_BOT_TOKEN` — Blip bot (also legacy `BLIP_BOT_TOKEN` in `.claude/skills/slack-bot/.env`)
- `NOTION_TOKEN`, `BUGASURA_API_KEY` — archived trackers, leave for historical lookup

---

See `operating_model.md` for dispatch/merge/reviewer rules, `tooling_gotchas.md` for lessons learned, `SOUL.md` for the voice, and `reference_jira_workspace.md` for Jira API patterns.
