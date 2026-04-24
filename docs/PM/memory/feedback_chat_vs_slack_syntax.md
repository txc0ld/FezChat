---
name: Don't paste raw Slack mention syntax into Cowork chat replies
description: Slack mention/channel syntax (`<@U...>`, `<#C...>`) only renders inside Slack — in Cowork chat replies to John, it appears as literal angle-bracket text and looks broken
type: feedback
originSessionId: 134ab6d3-3752-4978-ae5b-a3722cdc2970
---
When summarising Slack actions back to John in the Cowork chat, NEVER include raw Slack mention syntax. Cowork's chat doesn't parse it — it shows up as literal `<@U0APF5888J1>` or `<#C0APT84EXAS>` text and looks like a bug.

Use human names instead:
- **Channels**: `#tay-tasks` not `<#C0APT84EXAS>`, `#blip-dev` not `<#C0AQCQZVBCG>`, `#blip-hangout` not `<#C0AQD990D3J>`
- **People**: `Tay` not `<@U0APF5888J1>`, `Fabs` not `<@U0AQ0A6L4RM>`, `John` not `<@U0AP33M11QF>` (or just don't tag yourself when talking to yourself)

**Why:** John caught this 2026-04-24 after I summarised dispatches with `dispatched to <#C0APT84EXAS>` — looked broken even though the Slack tagging itself was fine. Slack mention syntax is a Slack rendering primitive, not a universal markdown thing.

**How to apply:**
- Slack messages: use `<@USER_ID>` and `<#CHANNEL_ID>` so they render as @mentions and #channel-links and fire pings.
- Cowork chat (responses to John, status updates, summaries): use plain `Tay` / `#tay-tasks` style. Always.
- Memory files: same — plain names, since they're written for future-me reading in Cowork chat context.

This rule overlaps with `slack_rules.md` (which is about *outbound* Slack syntax). This one is specifically about NOT carrying that syntax back into chat replies.
