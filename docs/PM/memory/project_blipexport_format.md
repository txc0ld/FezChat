---
name: .blipexport file format
description: The encrypted account export format for PR #186, including magic header, version byte, and rationale for why it's layered this way
type: project
---

`.blipexport` files use this layout (established 2026-04-14 during PR #186 review):

```
[4 bytes] magic = 'BLIP' (ASCII)
[1 byte]  version = 0x01
[16 bytes] KDF salt (Argon2 / PBKDF2 salt, per-export random)
[12 bytes] AES-GCM nonce (per-export random)
[N bytes]  ciphertext
[16 bytes] GCM auth tag
```

**Why:** The original PR #186 wrote just `[nonce | ciphertext | tag]` with no header, meaning future versions can't detect old-format files or fail gracefully on corrupt/unknown files. Adding BLIP + version byte lets us evolve the format without breaking old backups. Name stays `BLIP` (not `HYBL`) because the export originated before the HeyBlip rename and it's an internal file-format identifier — no user-visible impact.

**How to apply:** When touching export/import code, always verify the 4-byte magic first, dispatch on version byte, and return a clean `Unsupported export format version N — please update the app` error on unknown versions. Never try to parse an unknown version as v1.
