---
name: Bugasura API documentation (DEPRECATED — read-only archive)
description: Bugasura was the issue tracker from 2026-04-13 to 2026-04-24. Notion took over 2026-04-24. Use reference_notion_workspace.md for the live tracker. This file is kept for historical lookup of imported tickets only.
type: reference
originSessionId: 6e15e31b-7115-4971-bf13-07d171f32b25
---

> **DEPRECATED 2026-04-24.** Bugasura is now read-only archive at https://my.bugasura.io/HeyBlip — used for historical lookup of tickets imported into Notion (HEY-N IDs preserved on the Notion side via the `Bugasura URL` property). All new tickets and edits live in Notion — see [reference_notion_workspace.md](reference_notion_workspace.md). The API details below remain accurate for read-only queries against the archive but should not be used for write operations.


## Bugasura REST API Reference

- **Base URL:** `https://api.bugasura.io/v1` — the `/v1/` prefix is MANDATORY. CLAUDE.md was missing it until PR #254 (HEY1308) fixed the curl examples.
- **Auth:** `Authorization: Basic <api_key>` header on every request.
- **Encoding:** `application/x-www-form-urlencoded`, NOT JSON. Use `--data-urlencode` with curl. JSON body is silently ignored.
- **Responses:** JSON.

### Team & Project IDs (HeyBlip)

| | |
|---|---|
| team_id | 101842 (Mesh Works) |
| project_id | 135167 (HeyBlip, prefix HEY) |
| sprint_id | 152746 (Linear Import) — primary, status COMPLETED but still receiving new tickets |
| sprint_id | 153022 (Audit Gaps — Apr 2026) — secondary, status SCHEDULED, 44 tickets, mostly Fixed |
| sprint_id | 152741 (My First Sprint) — defunct/deleted 2026-04-13 |
| owner user_id | 89085 (John McKean) |

### Canonical list-issues curl (verified working 2026-04-24)

```bash
curl -s -G \
  -H "Authorization: Basic <see docs/PM/SECRETS.md $BUGASURA_API_KEY>" \
  --data-urlencode "team_id=101842" \
  --data-urlencode "project_id=135167" \
  --data-urlencode "sprint_id=152746" \
  --data-urlencode "max_results=100" \
  --data-urlencode "start_at=0" \
  "https://api.bugasura.io/v1/issues/list"
```

Response shape: `{status, message, issue_list: [{issue_key, issue_id, summary, status, severity, ...}], nrows, total_rows, start_at, max_results}`. `issue_key` is the numeric ID (e.g. 1620525), `issue_id` is the HEY-prefixed string (e.g. HEY1304).

---

### Issues — VERIFIED via testing

| Method | Endpoint | Params |
|---|---|---|
| POST | `/v1/issues/add` | team_id, project_id, sprint_id, summary (required), description, type, status, severity, tags |
| POST | `/v1/issues/update` | team_id, project_id, **sprint_id (REQUIRED)**, issue_key, ... |
| POST | `/v1/issues/delete` | team_id, project_id, issue_key (numeric like 1605380, NOT `HEY-243`) |
| GET | `/v1/issues/get` | team_id, project_id, issue_key |
| GET | `/v1/issues/list` | **WORKS** — requires `team_id`+`project_id`+`sprint_id`+`max_results` (all four). HEY1309 closed 2026-04-24 after re-verification. Earlier "Invalid URL." was from a missing required param, not a server bug. |

#### Issue field values — verified 2026-04-21

- **`summary`** — title field. NOT `title`. 
- **`severity`** — `LOW`, `MEDIUM`, `HIGH`, `CRITICAL`. NOT `priority`.
- **`type`** (or `issue_type` on add) — verified values used successfully today: `BUG`, `TECH-DEBT`, `FEATURE`, `POLISH`. All four confirmed accepted on `/v1/issues/add`.
- **`status`** — case-sensitive: `"New"`, `"In Progress"`, `"Fixed"`, `"Not Fixed"`, `"Released"`, `"Cancelled"`, `"Closed"`. NOT `"CLOSED"`, NOT `"IN_PROGRESS"`.
- **`tags`** — comma-separated string, e.g. `"Bug,Protocol,Infra"`.

### Other endpoints

| Method | Endpoint | Params |
|---|---|---|
| GET | `/v1/teams/list` | (none) |
| GET | `/v1/projects/list` | team_id |
| GET | `/v1/sprints/list` | team_id, project_id |
| POST | `/v1/issues/comments/add` | team_id, issue_key, comment |
| GET | `/v1/issues/comments/list` | team_id, issue_key |
| POST | `/v1/issues/assignees/add` | team_id, issue_key, assignee_id |
| POST | `/v1/issues/attachments/add` | team_id, issue_key, (file multipart) |

### List pagination

- `max_results` controls page size (default 10, max 100 per page even if 250 requested).
- `start_at` is 0-based offset.
- Response includes `total_rows`, `nrows`, `start_at`.

---

### Canonical add-issue curl

```bash
curl -s -X POST "https://api.bugasura.io/v1/issues/add" \
  -H "Authorization: Basic <see docs/PM/SECRETS.md $BUGASURA_API_KEY>" \
  --data-urlencode "team_id=101842" \
  --data-urlencode "project_id=135167" \
  --data-urlencode "sprint_id=152746" \
  --data-urlencode "summary=[AREA] Short title" \
  --data-urlencode "description=Body text (supports markdown — newlines, bullets, code fences)" \
  --data-urlencode "type=BUG" \
  --data-urlencode "severity=MEDIUM"
```

---

### Gotchas

1. **`/v1/` prefix is mandatory** — dropping it returns garbled errors. CLAUDE.md's example was stale before PR #254 fixed it.
2. **Form-encoded, not JSON** — `Content-Type: application/x-www-form-urlencoded`. JSON body silently ignored.
3. **Delete uses `issue_key`** (numeric) not `issue_id` (HEY-prefixed string).
4. **`sprint_id` is REQUIRED for `/v1/issues/update`** — without it the API returns "Report ID cannot be empty". Undocumented but confirmed 2026-04-13.
5. **Status values case-sensitive** — `"In Progress"` with space, not underscore.
6. **Field names differ from Linear** — `summary` (not `title`), `severity` (not `priority`). Priority field exists in spec but is unreliable — the API has returned P2 when P1 was sent. Don't set priority programmatically; use severity.
7. **`/v1/issues/list` requires all 4 params** — `team_id`, `project_id`, `sprint_id`, `max_results`. Drop any one and it returns "Invalid URL." Earlier HEY1309 belief that the endpoint was broken was wrong; closed 2026-04-24 after re-verification.
8. **`description` supports markdown** — newlines, bullets, quotes, code fences all preserved.

**How to apply:** Use this reference whenever creating, updating, or querying Bugasura issues via API. Always `POST` form-encoded with the `/v1/` prefix.
