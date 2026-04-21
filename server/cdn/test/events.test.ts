import {
  env,
  createExecutionContext,
  waitOnExecutionContext,
} from "cloudflare:test";
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
  neon: () => {
    const events = ((globalThis as any).__blipCdnMockEvents ??= []) as MockEvent[];
    return async (strings: TemplateStringsArray, ...values: unknown[]) => {
      const normalized = strings.join(" ").replace(/\s+/g, " ").trim().toLowerCase();

      if (normalized.startsWith("select id, name, latitude, longitude, radius_meters, start_date, end_date, location, description, image_url, organizer_signing_key, attendee_count, category from events")) {
        return [...events].sort((a, b) => a.start_date.localeCompare(b.start_date));
      }

      if (normalized.startsWith("insert into events")) {
        const row: MockEvent = {
          id: crypto.randomUUID(),
          name: values[0] as string,
          latitude: values[1] as number,
          longitude: values[2] as number,
          radius_meters: values[3] as number,
          start_date: values[4] as string,
          end_date: values[5] as string,
          location: (values[6] as string | null) ?? null,
          description: (values[7] as string | null) ?? null,
          image_url: (values[8] as string | null) ?? null,
          organizer_signing_key: (values[9] as string | null) ?? null,
          attendee_count: (values[10] as number | null) ?? 0,
          category: (values[11] as string | null) ?? null,
        };
        events.push(row);
        return [row];
      }

      if (normalized.startsWith("update events set")) {
        const id = values[values.length - 1] as string;
        const existing = events.find((e) => e.id === id);
        if (!existing) return [];
        existing.name = values[0] as string;
        existing.latitude = values[1] as number;
        existing.longitude = values[2] as number;
        existing.radius_meters = values[3] as number;
        existing.start_date = values[4] as string;
        existing.end_date = values[5] as string;
        existing.location = (values[6] as string | null) ?? null;
        existing.description = (values[7] as string | null) ?? null;
        existing.image_url = (values[8] as string | null) ?? null;
        existing.organizer_signing_key = (values[9] as string | null) ?? null;
        existing.attendee_count = (values[10] as number | null) ?? 0;
        existing.category = (values[11] as string | null) ?? null;
        return [existing];
      }

      if (normalized.startsWith("delete from events")) {
        const id = values[0] as string;
        const index = events.findIndex((e) => e.id === id);
        if (index === -1) return [];
        const [removed] = events.splice(index, 1);
        return [{ id: removed.id }];
      }

      throw new Error(`Unexpected SQL in test: ${normalized}`);
    };
  },
}));

import worker from "../src/index";

type WorkerEnv = typeof env;
const ADMIN_KEY = "test-internal-api-key";

async function request(
  method: string,
  path: string,
  body?: Record<string, unknown>,
  headers: Record<string, string> = {}
): Promise<Response> {
  const init: RequestInit = {
    method,
    headers: { "Content-Type": "application/json", ...headers },
  };
  if (body !== undefined) init.body = JSON.stringify(body);

  const req = new Request(`http://localhost${path}`, init);
  const ctx = createExecutionContext();
  const res = await worker.fetch(req, env as unknown as WorkerEnv, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

function validEventBody(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    name: "Splendour in the Grass",
    latitude: -28.7425,
    longitude: 153.561,
    radiusMeters: 2000,
    startDate: "2026-07-17T00:00:00Z",
    endDate: "2026-07-19T23:59:59Z",
    location: "North Byron Parklands, Byron Bay NSW",
    description: "Australia's premier music festival.",
    imageURL: "",
    organizerSigningKey: "",
    attendeeCount: 35000,
    category: "festival",
    ...overrides,
  };
}

beforeEach(() => {
  (globalThis as any).__blipCdnMockEvents = [];
});

describe("GET /manifests/events.json", () => {
  it("returns an empty manifest when the table is empty", async () => {
    const res = await request("GET", "/manifests/events.json");
    expect(res.status).toBe(200);
    expect(res.headers.get("Cache-Control")).toBe("public, max-age=3600");

    const body = (await res.json()) as {
      version: number;
      signature: unknown;
      signingKey: unknown;
      events: unknown[];
    };
    expect(body.version).toBe(1);
    // With MANIFEST_SIGNING_KEY set in vitest.config.ts, the worker signs even an empty
    // events array. Detailed signature/canonicalisation coverage lives in
    // test/manifest-signature.test.ts.
    expect(typeof body.signature).toBe("string");
    expect(typeof body.signingKey).toBe("string");
    expect(body.events).toEqual([]);
  });

  it("maps DB rows to the iOS EventManifest shape", async () => {
    await request("POST", "/v1/events", validEventBody(), {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });

    const res = await request("GET", "/manifests/events.json");
    expect(res.status).toBe(200);

    const body = (await res.json()) as { events: Array<Record<string, unknown>> };
    expect(body.events).toHaveLength(1);
    const event = body.events[0];
    expect(event.name).toBe("Splendour in the Grass");
    expect(event.radiusMeters).toBe(2000);
    expect(event.startDate).toBe("2026-07-17T00:00:00Z");
    expect(event.imageURL).toBe("");
    expect(event.category).toBe("festival");
    // Not snake_case:
    expect(event).not.toHaveProperty("radius_meters");
    expect(event).not.toHaveProperty("start_date");
  });
});

describe("POST /v1/events (admin)", () => {
  it("rejects requests without the INTERNAL_API_KEY", async () => {
    const res = await request("POST", "/v1/events", validEventBody());
    expect(res.status).toBe(401);
  });

  it("rejects requests with a wrong key", async () => {
    const res = await request("POST", "/v1/events", validEventBody(), {
      Authorization: "Bearer wrong-key",
    });
    expect(res.status).toBe(401);
  });

  it("creates an event with the correct key and returns 201", async () => {
    const res = await request("POST", "/v1/events", validEventBody(), {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });
    expect(res.status).toBe(201);

    const body = (await res.json()) as Record<string, unknown>;
    expect(body.id).toBeTypeOf("string");
    expect(body.name).toBe("Splendour in the Grass");
  });

  it("rejects missing required fields", async () => {
    const body = validEventBody();
    delete (body as Record<string, unknown>).name;

    const res = await request("POST", "/v1/events", body, {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });
    expect(res.status).toBe(400);
  });

  it("rejects out-of-range coordinates", async () => {
    const res = await request("POST", "/v1/events", validEventBody({ latitude: 120 }), {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });
    expect(res.status).toBe(400);
  });

  it("rejects invalid categories", async () => {
    const res = await request("POST", "/v1/events", validEventBody({ category: "rave" }), {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });
    expect(res.status).toBe(400);
  });

  it("rejects endDate before startDate", async () => {
    const res = await request(
      "POST",
      "/v1/events",
      validEventBody({
        startDate: "2026-07-19T00:00:00Z",
        endDate: "2026-07-17T00:00:00Z",
      }),
      { Authorization: `Bearer ${ADMIN_KEY}` }
    );
    expect(res.status).toBe(400);
  });
});

describe("PUT /v1/events/:id (admin)", () => {
  it("updates an existing event", async () => {
    const createRes = await request("POST", "/v1/events", validEventBody(), {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });
    const created = (await createRes.json()) as { id: string };

    const putRes = await request(
      "PUT",
      `/v1/events/${created.id}`,
      validEventBody({ name: "Splendour 2027", attendeeCount: 40000 }),
      { Authorization: `Bearer ${ADMIN_KEY}` }
    );
    expect(putRes.status).toBe(200);
    const updated = (await putRes.json()) as Record<string, unknown>;
    expect(updated.name).toBe("Splendour 2027");
    expect(updated.attendeeCount).toBe(40000);
  });

  it("returns 404 for unknown IDs", async () => {
    const res = await request(
      "PUT",
      "/v1/events/00000000-0000-0000-0000-000000000000",
      validEventBody(),
      { Authorization: `Bearer ${ADMIN_KEY}` }
    );
    expect(res.status).toBe(404);
  });
});

describe("DELETE /v1/events/:id (admin)", () => {
  it("deletes an existing event and returns 204", async () => {
    const createRes = await request("POST", "/v1/events", validEventBody(), {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });
    const created = (await createRes.json()) as { id: string };

    const delRes = await request("DELETE", `/v1/events/${created.id}`, undefined, {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });
    expect(delRes.status).toBe(204);

    const listRes = await request("GET", "/v1/events", undefined, {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });
    const body = (await listRes.json()) as { events: unknown[] };
    expect(body.events).toEqual([]);
  });

  it("returns 404 when deleting unknown IDs", async () => {
    const res = await request(
      "DELETE",
      "/v1/events/00000000-0000-0000-0000-000000000000",
      undefined,
      { Authorization: `Bearer ${ADMIN_KEY}` }
    );
    expect(res.status).toBe(404);
  });
});

describe("GET /v1/events (admin list)", () => {
  it("requires the INTERNAL_API_KEY", async () => {
    const res = await request("GET", "/v1/events");
    expect(res.status).toBe(401);
  });

  it("returns all events when authorized", async () => {
    await request("POST", "/v1/events", validEventBody({ name: "A" }), {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });
    await request("POST", "/v1/events", validEventBody({ name: "B" }), {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });

    const res = await request("GET", "/v1/events", undefined, {
      Authorization: `Bearer ${ADMIN_KEY}`,
    });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { events: Array<{ name: string }> };
    expect(body.events.map((e) => e.name).sort()).toEqual(["A", "B"]);
  });
});
