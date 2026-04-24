# PM Secrets

The PM session needs four secrets. They are NOT in this repo — they live in a gitignored env file on John's machine.

## Where the file is

```
~/heyblip/.claude/skills/secrets/.env
```

This path is gitignored via `.claude/` (already in `.gitignore`). The file should never be committed.

## What's in it

```bash
# Notion personal integration token. Authenticated as "Claude.ai HeyBlip" bot in the HeyBlip workspace.
# Rotates: quarterly. Last rotation: 2026-04-24.
# Get from: https://www.notion.so/profile/integrations (John's account)
export NOTION_TOKEN="ntn_..."

# Slack bot token for the "Blip" bot (App ID A0APDURFTMH, Bot User U0APGUH16SZ).
# Scopes: chat:write, channels:read, channels:history, files:read, users:read, etc.
# Rotates: only on incident. Get from: https://api.slack.com/apps/A0APDURFTMH/oauth
export SLACK_BOT_TOKEN="xoxb-10798501476390-..."

# Bugasura API key. Bugasura is read-only archive only post-2026-04-24, but the key
# still works for historical lookups of imported tickets.
# Get from: https://my.bugasura.io/ → Settings → API
export BUGASURA_API_KEY="ef611198..."

# GitHub PAT for iamjohnnymac. Scopes: repo, workflow.
# Rotates: per GitHub policy. Used by gh CLI and by curl against api.github.com.
# Already embedded in ~/heyblip/.git/config (https://ghp_<token>@github.com/...) for git push,
# but this env-var copy is for direct API curls.
export GITHUB_PAT="ghp_..."
```

## How to verify each one works

```bash
source ~/heyblip/.claude/skills/secrets/.env

# Notion — should print "Claude.ai HeyBlip"
curl -s -H "Authorization: Bearer $NOTION_TOKEN" -H "Notion-Version: 2022-06-28" \
  "https://api.notion.com/v1/users/me" | jq .name

# Slack bot — should print {"ok":true,"team":"The Mesh","user":"Blip",...}
curl -s -H "Authorization: Bearer $SLACK_BOT_TOKEN" "https://slack.com/api/auth.test" | jq .

# Bugasura — list HEY-1318 (any HEY-N you know exists)
curl -s -G -H "Authorization: Basic $BUGASURA_API_KEY" \
  --data-urlencode "team_id=101842" --data-urlencode "project_id=135167" \
  --data-urlencode "sprint_id=152746" --data-urlencode "max_results=5" \
  "https://api.bugasura.io/v1/issues/list" | jq '.issue_list[0].issue_id'

# GitHub PAT — list open PRs
gh pr list --repo txc0ld/heyblip --state open
```

If any of these fail, the secret is stale or wrong — surface to John, do NOT scrape from disk.

## Rotation

If a token is compromised or rotated:
1. John updates the env file directly.
2. Cowork (you) does NOT need to be re-prompted — next `source` picks up the new value.
3. If it's the Notion token, also update `~/.auto-memory/reference_notion_workspace.md` if you want future-future-PMs to see the rotation date (purely informational — the actual value lives only in `.env`).

## What's NOT in this file

- Apple Developer / App Store Connect credentials — those are John's only, in his macOS Keychain + GitHub Actions Secrets. PM doesn't touch the TestFlight pipeline directly.
- Cloudflare Workers (`wrangler` auth) — John's terminal only.
- Sentry API tokens — not currently provisioned for PM. Sentry dashboard cleanup is a manual John-clicks task.
- Apple Developer / ASC API key — same as above, John's only.

## File creation template

If `~/heyblip/.claude/skills/secrets/.env` doesn't exist yet, copy `docs/PM/SECRETS.example` to that path and have John populate the actual values. The example file has the variable names but no values.
