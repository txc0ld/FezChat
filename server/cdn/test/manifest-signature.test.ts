import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { describe, it, expect, beforeEach, vi } from "vitest";

interface MockEvent {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  radius_meters: number;
  start_date: string;
  end_date: string;
  location: string | null;
  description: string | null;
  image_url: string | null;
  organizer_signing_key: string | null;
  attendee_count: number | null;
  category: string | null;
}

vi.mock("@neondatabase/serverless", () => ({
  neon: () => async (strings: TemplateStringsArray) => {
    const events = ((globalThis as any).__manifestSigEvents ??= []) as MockEvent[];
    const sql = strings.join(" ").toLowerCase();
    if (sql.includes("select id, name, latitude, longitude, radius_meters")) {
      return [...events].sort((a, b) => a.start_date.localeCompare(b.start_date));
    }
    throw new Error("unexpected SQL in manifest-signature test");
  },
}));

import worker, {
  rowToCanonicalEvent,
  signCanonicalEvents,
  toCanonicalIso,
} from "../src/index";

type WorkerEnv = typeof env;

// ===========================================================================
// Cross-language fixture: this exact byte string must also be reproduced by
// Swift's JSONEncoder([.sortedKeys, .iso8601]) on an equivalent ManifestEvent
// array. The matching assertion lives in
// Packages/BlipCrypto/Tests/ManifestCanonicalEncodingTests.swift — keep them
// in lockstep when changing the canonical format.
// ===========================================================================
const FIXTURE_CANONICAL =
  '[{"attendeeCount":35000,"category":"festival","endDate":"2026-07-19T23:59:59Z","id":"550E8400-E29B-41D4-A716-446655440000","latitude":-28.7425,"location":"North Byron Parklands","longitude":153.561,"name":"Splendour in the Grass","organizerSigningKey":"","radiusMeters":2000,"startDate":"2026-07-17T00:00:00Z"}]';

// Public key half of MANIFEST_SIGNING_KEY (vitest.config.ts) — the worker
// returns this in `manifest.signingKey` and the iOS client uses it to verify.
const FIXTURE_PUBLIC_KEY_B64 = "ebVWLo/mVPlAeLES6KmLp5AfhTrmlb7X4OORC60ElmQ=";

// Ed25519 is deterministic (RFC 8032), so signing FIXTURE_CANONICAL with the
// fixture seed always produces this exact 64-byte signature.
const FIXTURE_SIGNATURE_B64 =
  "Fmc5giGePXpcBhcUMLzQ3QLCPRmTQsjIK6vCyPFJt93gfVlUG0UUsL0FTA1zW1k1hw9v5zMDi31fCEpvUvWBBA==";

const FIXTURE_ROW: MockEvent = {
  id: "550e8400-e29b-41d4-a716-446655440000", // lowercase from DB; canonicaliser uppercases
  name: "Splendour in the Grass",
  latitude: -28.7425,
  longitude: 153.561,
  radius_meters: 2000,
  start_date: "2026-07-17T00:00:00.000Z", // millis present; canonicaliser drops them
  end_date: "2026-07-19T23:59:59.000Z",
  location: "North Byron Parklands",
  description: null, // omitted by canonicaliser
  image_url: null, // omitted by canonicaliser
  organizer_signing_key: null, // canonicalises to ""
  attendee_count: 35000,
  category: "festival",
};

beforeEach(() => {
  (globalThis as any).__manifestSigEvents = [FIXTURE_ROW];
});

describe("rowToCanonicalEvent", () => {
  it("produces the cross-language canonical bytes", () => {
    const canonical = JSON.stringify([rowToCanonicalEvent(FIXTURE_ROW)]);
    expect(canonical).toBe(FIXTURE_CANONICAL);
  });

  it("uppercases UUIDs, drops millis, omits nullable fields", () => {
    const out = rowToCanonicalEvent(FIXTURE_ROW);
    expect(out.id).toBe("550E8400-E29B-41D4-A716-446655440000");
    expect(out.startDate).toBe("2026-07-17T00:00:00Z");
    expect(out).not.toHaveProperty("description");
    expect(out).not.toHaveProperty("imageURL");
    expect(out.organizerSigningKey).toBe("");
  });

  it("omits attendeeCount fallback only when DB value is null", () => {
    const withZero = rowToCanonicalEvent({ ...FIXTURE_ROW, attendee_count: 0 });
    expect(withZero.attendeeCount).toBe(0);
    const withNull = rowToCanonicalEvent({ ...FIXTURE_ROW, attendee_count: null });
    // Worker preserves the iOS contract that attendeeCount is always present.
    expect(withNull.attendeeCount).toBe(0);
  });
});

describe("toCanonicalIso", () => {
  it("normalises Date and string inputs to second-precision ISO with Z", () => {
    expect(toCanonicalIso(new Date("2026-07-17T00:00:00.123Z"))).toBe("2026-07-17T00:00:00Z");
    expect(toCanonicalIso("2026-07-17T00:00:00.987Z")).toBe("2026-07-17T00:00:00Z");
    expect(toCanonicalIso("2026-07-17T00:00:00Z")).toBe("2026-07-17T00:00:00Z");
  });

  it("rejects garbage input rather than emitting Invalid Date", () => {
    expect(() => toCanonicalIso("not a date")).toThrow();
  });
});

describe("signCanonicalEvents", () => {
  it("returns the deterministic Ed25519 signature for the fixture", async () => {
    const signed = await signCanonicalEvents(FIXTURE_CANONICAL, env.MANIFEST_SIGNING_KEY!);
    expect(signed.publicKey).toBe(FIXTURE_PUBLIC_KEY_B64);
    expect(signed.signature).toBe(FIXTURE_SIGNATURE_B64);
  });

  it("verifies via crypto.subtle round-trip", async () => {
    const signed = await signCanonicalEvents(FIXTURE_CANONICAL, env.MANIFEST_SIGNING_KEY!);
    const pubKey = await crypto.subtle.importKey(
      "raw",
      base64ToBytes(signed.publicKey),
      { name: "Ed25519" },
      false,
      ["verify"]
    );
    const ok = await crypto.subtle.verify(
      "Ed25519",
      pubKey,
      base64ToBytes(signed.signature),
      new TextEncoder().encode(FIXTURE_CANONICAL)
    );
    expect(ok).toBe(true);
  });

  it("rejects a tampered message", async () => {
    const signed = await signCanonicalEvents(FIXTURE_CANONICAL, env.MANIFEST_SIGNING_KEY!);
    const pubKey = await crypto.subtle.importKey(
      "raw",
      base64ToBytes(signed.publicKey),
      { name: "Ed25519" },
      false,
      ["verify"]
    );
    const tampered = FIXTURE_CANONICAL.replace("Splendour", "splendour");
    const ok = await crypto.subtle.verify(
      "Ed25519",
      pubKey,
      base64ToBytes(signed.signature),
      new TextEncoder().encode(tampered)
    );
    expect(ok).toBe(false);
  });

  it("rejects a malformed signing key length", async () => {
    await expect(signCanonicalEvents("[]", "QUJD" /* "ABC" — 3 bytes */)).rejects.toThrow(
      /64 bytes/
    );
  });
});

describe("GET /manifests/events.json (signed)", () => {
  it("returns matching signature, signingKey, and canonical events bytes", async () => {
    const req = new Request("http://localhost/manifests/events.json");
    const ctx = createExecutionContext();
    const res = await worker.fetch(req, env as unknown as WorkerEnv, ctx);
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      version: number;
      signature: string;
      signingKey: string;
      events: Array<Record<string, unknown>>;
    };

    expect(body.version).toBe(1);
    expect(body.signingKey).toBe(FIXTURE_PUBLIC_KEY_B64);

    // Re-canonicalise the events the same way the iOS client will, then check
    // it round-trips against the signature embedded in the response.
    const reCanonical = JSON.stringify(body.events);
    expect(reCanonical).toBe(FIXTURE_CANONICAL);

    const pubKey = await crypto.subtle.importKey(
      "raw",
      base64ToBytes(body.signingKey),
      { name: "Ed25519" },
      false,
      ["verify"]
    );
    const ok = await crypto.subtle.verify(
      "Ed25519",
      pubKey,
      base64ToBytes(body.signature),
      new TextEncoder().encode(reCanonical)
    );
    expect(ok).toBe(true);
  });

  it("returns null signature/signingKey when MANIFEST_SIGNING_KEY is unset", async () => {
    const original = env.MANIFEST_SIGNING_KEY;
    try {
      (env as { MANIFEST_SIGNING_KEY?: string }).MANIFEST_SIGNING_KEY = undefined;
      const req = new Request("http://localhost/manifests/events.json");
      const ctx = createExecutionContext();
      const res = await worker.fetch(req, env as unknown as WorkerEnv, ctx);
      await waitOnExecutionContext(ctx);

      expect(res.status).toBe(200);
      const body = (await res.json()) as { signature: unknown; signingKey: unknown };
      expect(body.signature).toBeNull();
      expect(body.signingKey).toBeNull();
    } finally {
      (env as { MANIFEST_SIGNING_KEY?: string }).MANIFEST_SIGNING_KEY = original;
    }
  });
});

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}
