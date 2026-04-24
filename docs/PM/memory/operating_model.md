---
name: Operating model — dispatch, merge, reviewer, PM boundaries
description: How work flows end-to-end. Dispatch channels, who merges what, Opus pinning, PM-vs-reviewer role split. Updated 2026-04-21 EOD.
type: project
originSessionId: 6e15e31b-7115-4971-bf13-07d171f32b25
---
## Dispatch

- **Trunk-based dev**, short-lived branches named `type/HEY-XXX-short-description`. One Notion task per task.
- **John = infra/backend** (Codex or Claude Code). **Tay = frontend/UI** (Claude Code). Both non-technical — prompts must hand-hold.
- **Cowork dispatches full prompts** to `#jmac-tasks` / `#tay-tasks` as Blip bot via curl. Prompt goes directly in the Slack message as a copy-pasteable code block — never "see the Notion task description". See `slack_rules.md` for formatting.
- **Dispatch resumes tomorrow (2026-04-22).** Today (2026-04-21) John said "no Tay dispatch" — that was a one-day-only exception. Unless John says otherwise, resume normal Notion task → task-channel notification flow from tomorrow.
- **Today's dispatch drafts** at `~/FezChat/pending-dispatch/` were consumed into PRs #251-#254. Folder should be empty tomorrow unless fresh drafts are staged.

## Capture rule

**Standing rule from 2026-04-21 onward: capture all bugs big or small.** When reviewing PRs, working in code, or chasing Sentry noise, every finding gets a Notion task filed in the same pass — no mental notes, no "I'll remember this later". See `feedback_file_review_findings.md`.

## Merge pipeline

- **Reviewer task has GitHub PAT** and merges PRs directly without formal approval. Merge authority lives with the reviewer, not John. John no longer clicks merge on every PR — only when the PM flags specifically for escalation.
- **PM does NOT merge PRs.** PM's job ends at branch pushed + PR opened + `#blip-dev` notification. Reviewer handles the merge click.
- **Never merge on yellow CI** — wait for green.
- **Post-merge**: verify the change actually landed on `main` (read code, don't trust commit msg). Flag the Notion task for closure.
- **PAT self-approval limitation**: GitHub PAT (iamjohnnymac) cannot approve PRs where the PAT owner pushed the last commit. Workaround: merge directly.

### Reviewer pre-flight — added 2026-04-21

Before reviewing a PR, reviewer MUST `git fetch origin && git checkout main && git pull` so the local base matches origin. Stale-local-main bit us twice today on PRs #250 and #252 — see `tooling_gotchas.md`. Tracked by **HEY1312**.

## Model pinning

- **Opus 4.7 pinned** for all reviewer/merger tasks. Don't downgrade — the reasoning quality on diffs is materially better and we've seen clean catches it wouldn't make on Sonnet.
- PM sessions default to whatever the session was spawned on; no explicit pin.

## Ticket status — PM boundary

- **PM NEVER transitions Notion task status.** Cowork/John manages `New → In Progress → Fixed → Closed` transitions end-to-end.
- PM never posts as John, never reveals bot orchestration, never merges PRs, never touches ticket status.
- If a PM session fixes something via PR merge, note it in `project_history.md` as "Fixed by PR #XYZ — awaiting transition" and stop.

## Escalation to John

Only ping John for:
- Merge conflicts the reviewer can't resolve without direction.
- Worker deploys (`wrangler deploy` commands go to `#jmac-tasks`).
- CI failures the reviewer can't diagnose.
- Sentry dashboard clicks (no API for "Resolved in next release").
- Conflicts or policy decisions — e.g., scope creep, dependency adds.
