---
name: Project history archive (Sprints 1-3, Apr 2026)
description: Archived sprint details, merged PR lists, and resolved issues from before Apr 14. Read only if you need historical context on a specific old PR or decision.
type: project
originSessionId: bbbc0954-8624-408e-9557-ba247c463544
---
## Archived — see project_history.md for current state

This file contains completed sprint details that are no longer needed in active memory.
For current state, dispatched prompts, and open backlog, read project_history.md.

## Rebrand (COMPLETE)
- FestiChat → Blip → HeyBlip (user-facing). Bundle ID au.heyblip.Blip. GitHub repo txc0ld/heyblip.

## Auth Pivot (COMPLETE)
- Dropped Twilio/SMS. Now email + social login. PhoneVerificationService.swift deleted.

## Events Pivot (COMPLETE, 2026-04-03)
- Broadened from festivals-only to all high-density events.

## Sprint 1: 81 bare try? fixed. CLAUDE.md rewritten.
## Sprint 2 (COMPLETE, 2026-04-02): 14 PRs. Two-way encrypted DMs working.
## Sprint 3 (COMPLETE, 2026-04-05): Stability phase 7/7, UI polish, voice notes, background exec.

## Performance & Security Sprint (Apr 4-5)
- MessageService decomposed: 2,526 → 1,240 lines (PRs #113, #114)
- Keychain hardening (PR #112), Auth hardening (PR #110), Plaintext fallback fix (PR #109)
- Relay store-and-forward + broadcast + sender verification (PRs #111, #115)
- Security audit BDEV-179: all 10 child tickets resolved (PRs #122-#147)
- DM pipeline validated Perth↔Onslow. Duplicate channels fixed, sender attribution fixed, BLE flapping fixed.

## Merged PR List (Apr 4-8)
PRs #98-#119, #120-#123, #141-#147, #149. 381 tests passing. See git log for details.

## UI Audit (Apr 12-13)
- 85+ view files audited. 15 tickets (BDEV-242-256). 12 Done. 4 were falsely marked Done → post-merge verification process established.

## BRAID A/B Test (Apr 7)
- Tested dependency graph prompts vs prose. Identical output. No measurable advantage for well-scoped tasks.
