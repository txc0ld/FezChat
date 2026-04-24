---
name: Tooling gotchas — lessons learned that cost real time
description: Recurring failure modes in dispatch, Chrome automation, wrangler pipes, git worktrees, mobile approvals. Read before planning any orchestration.
type: feedback
originSessionId: 6e15e31b-7115-4971-bf13-07d171f32b25
---
## Stale local `main` bit us twice on 2026-04-21

- PR #250's first attempt branched off a stale local `~/heyblip/main` — pulled in 4 already-merged commits from #249 and looked like a scary-big diff.
- PR #252's operator step failed because the operator was standing on the wrong base.

**Why:** local `main` can trail `origin/main` after a batch of merges, and branching without fetching first silently includes already-merged commits in the diff.

**How to apply:** every dispatch prompt MUST include this as its pre-flight step:
```bash
git fetch origin && git checkout -b type/HEY-XXXX-short-description origin/main
```
Never branch from local `main` without fetching first. Reviewers must also `git fetch && git checkout main && git pull` before reviewing so the base matches origin. Tracked by **HEY1312**.

---

## Unsafe `node ... | wrangler secret put ...` silently uploads garbage

When setting `MANIFEST_SIGNING_KEY` on `blip-cdn` today via:
```bash
node scripts/generate-manifest-key.mjs | wrangler secret put MANIFEST_SIGNING_KEY
```
`node` crashed with `MODULE_NOT_FOUND`, the pipe delivered empty stdin to `wrangler`, and `wrangler` accepted the empty input as the production signing key. No validation anywhere. Happened twice before John spotted it.

**Why:** shell pipes don't propagate upstream exit codes by default, and `wrangler secret put` has no content validation — it just takes whatever bytes arrive on stdin.

**How to apply:** NEVER pipe a generator directly into `wrangler secret put`. Wrap secret uploads in a helper that:
1. Runs the generator to a tempfile.
2. Checks exit code.
3. Checks output shape (non-empty, expected length, base64-valid, etc.).
4. THEN pipes the tempfile into `wrangler`.

Tracked by **HEY1313**.

---

## Dispatch mobile approval push notifications don't arrive

Dispatch docs say mobile push surfaces approval requests. In practice John received zero phone pushes today — all approval prompts appeared only on his Mac.

**Why:** unclear — not a HeyBlip bug. Documented as external product feedback for Anthropic.

**How to apply:** orchestrate code-task spawns assuming John is at his Mac. Don't queue work that requires John to approve while he's mobile.

---

## PM-driving-Chrome-on-Sentry can wedge in long nav loops

The original PM session (`local_ca5b9e89`) got stuck in a long Chrome loop driving Sentry device-filter search. Had to leave it running while a fresh PM v2 took over.

**Why:** Sentry's UI has many conditional elements and async loads. A PM running through Chrome-MCP for filter tweaks burns huge turn counts.

**How to apply:**
- For Sentry work, prefer a user API token for programmatic queries.
- If Chrome is the only option, scope it tight: single click → single screenshot → next tool choice. Don't loop a PM through Chrome-Sentry filter adjustments.
- If a PM session has been driving Chrome on Sentry for more than ~10 turns without progress, abort and spin up a fresh session with a narrower task.

---

## Worktree collision on `~/heyblip`

John's local `~/heyblip` was on a stale branch AND `main` was locked to a worktree left by an idle code task. Cleanup required before he could `git checkout main`.

**Why:** code tasks that create git worktrees don't always clean up on exit. If a PM spawns multiple concurrent code tasks against the same repo without worktree isolation, the second task can collide on `main`.

**How to apply:**
- Code tasks that create worktrees should clean up on exit.
- PM should not spawn multiple concurrent code tasks against the same repo without explicit worktree isolation.
- If a user reports "can't check out main", first guess is an idle worktree lock — `git worktree list` and prune stale ones.
