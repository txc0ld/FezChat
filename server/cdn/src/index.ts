/**
 * Blip CDN worker.
 *
 * POST   /avatars/upload       — authenticated multipart upload, stores in R2
 * GET    /avatars/:id.jpg      — public avatar read from R2
 * GET    /manifests/events.json — public event manifest, DB-backed
 * GET    /manifests/*          — other static manifests (R2 passthrough)
 * GET    /v1/events            — admin list (INTERNAL_API_KEY)
 * POST   /v1/events            — admin create (INTERNAL_API_KEY)
 * PUT    /v1/events/:id        — admin update (INTERNAL_API_KEY)
 * DELETE /v1/events/:id        — admin delete (INTERNAL_API_KEY)
 * GET    /health               — liveness check
 */

export interface Env {
  AVATARS: R2Bucket;
  JWT_SECRET?: string;
  DATABASE_URL?: string;
  INTERNAL_API_KEY?: string;
  CORS_ORIGIN?: string;
  MAX_AVATAR_BYTES?: string;
}

interface JWTPayload {
  sub: string;
  npk: string;
  iat: number;
  exp: number;
}

interface EventRow {
  id: string;
  name: string;
  latitude: number;
  longitude: number;
  radius_meters: number;
  start_date: string | Date;
  end_date: string | Date;
  location: string | null;
  description: string | null;
  image_url: string | null;
  organizer_signing_key: string | null;
  attendee_count: number | null;
  category: string | null;
}

interface EventInput {
  name: string;
  latitude: number;
  longitude: number;
  radiusMeters: number;
  startDate: string;
  endDate: string;
  location?: string | null;
  description?: string | null;
  imageURL?: string | null;
  organizerSigningKey?: string | null;
  attendeeCount?: number | null;
  category?: string | null;
}

const DEFAULT_MAX_AVATAR_BYTES = 2 * 1024 * 1024; // 2MB
const MANIFEST_VERSION = 1;
const ALLOWED_CATEGORIES = new Set(["festival", "sport", "marathon", "concert", "other"]);

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const corsHeaders = getCorsHeaders(env);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders });
    }

    try {
      if (request.method === "POST" && url.pathname === "/avatars/upload") {
        return await handleAvatarUpload(request, env, corsHeaders);
      }

      const avatarMatch = url.pathname.match(/^\/avatars\/([a-zA-Z0-9_-]+)\.jpg$/);
      if (request.method === "GET" && avatarMatch) {
        return await handleAvatarGet(avatarMatch[1], env, corsHeaders);
      }

      if (request.method === "GET" && url.pathname === "/manifests/events.json") {
        return await handleEventsManifest(env, corsHeaders);
      }

      const manifestMatch = url.pathname.match(/^\/manifests\/([a-zA-Z0-9_\-/.]+\.json)$/);
      if (request.method === "GET" && manifestMatch) {
        return await handleManifestGet(manifestMatch[1], env, corsHeaders);
      }

      if (url.pathname === "/v1/events") {
        if (request.method === "GET") return await handleEventsList(request, env, corsHeaders);
        if (request.method === "POST") return await handleEventsCreate(request, env, corsHeaders);
      }

      const eventByIdMatch = url.pathname.match(/^\/v1\/events\/([0-9a-fA-F-]{36})$/);
      if (eventByIdMatch) {
        const eventId = eventByIdMatch[1];
        if (request.method === "PUT") return await handleEventsUpdate(request, env, eventId, corsHeaders);
        if (request.method === "DELETE") return await handleEventsDelete(request, env, eventId, corsHeaders);
      }

      if (request.method === "GET" && url.pathname === "/health") {
        return jsonResponse({ status: "ok" }, 200, corsHeaders);
      }

      return jsonResponse({ error: "Not found" }, 404, corsHeaders);
    } catch (err) {
      if (err instanceof HTTPError) {
        return jsonResponse({ error: err.message }, err.status, corsHeaders);
      }
      return jsonResponse({ error: "Internal server error" }, 500, corsHeaders);
    }
  },
};

// MARK: - Handlers

async function handleAvatarUpload(
  request: Request,
  env: Env,
  corsHeaders: Record<string, string>
): Promise<Response> {
  const claims = await validateJWT(request, env);
  const userId = claims.sub;

  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.includes("multipart/form-data")) {
    throw new HTTPError(400, "Expected multipart/form-data");
  }

  const formData = await request.formData();
  const file = formData.get("avatar");

  if (!file || !(file instanceof File)) {
    throw new HTTPError(400, "Missing avatar file");
  }

  const maxBytes = Number.parseInt(env.MAX_AVATAR_BYTES ?? "", 10) || DEFAULT_MAX_AVATAR_BYTES;
  if (file.size > maxBytes) {
    throw new HTTPError(413, `Avatar exceeds ${maxBytes} byte limit`);
  }

  const imageData = await file.arrayBuffer();

  // Validate JPEG magic bytes
  const header = new Uint8Array(imageData.slice(0, 3));
  if (header[0] !== 0xff || header[1] !== 0xd8 || header[2] !== 0xff) {
    throw new HTTPError(400, "Invalid JPEG file");
  }

  const key = `${userId}.jpg`;

  await env.AVATARS.put(key, imageData, {
    httpMetadata: {
      contentType: "image/jpeg",
      cacheControl: "public, max-age=3600",
    },
  });

  const avatarURL = `${new URL(request.url).origin}/avatars/${userId}.jpg`;

  return jsonResponse({ url: avatarURL }, 200, corsHeaders);
}

async function handleAvatarGet(
  userId: string,
  env: Env,
  corsHeaders: Record<string, string>
): Promise<Response> {
  const key = `${userId}.jpg`;
  const object = await env.AVATARS.get(key);

  if (!object) {
    return jsonResponse({ error: "Avatar not found" }, 404, corsHeaders);
  }

  const headers = new Headers(corsHeaders);
  headers.set("Content-Type", "image/jpeg");
  headers.set("Cache-Control", "public, max-age=3600");
  headers.set("ETag", object.httpEtag);

  return new Response(object.body, { status: 200, headers });
}

// MARK: - Manifest Handler

async function handleManifestGet(
  path: string,
  env: Env,
  corsHeaders: Record<string, string>
): Promise<Response> {
  const key = `manifests/${path}`;
  const object = await env.AVATARS.get(key);

  if (!object) {
    return jsonResponse({ error: "Manifest not found" }, 404, corsHeaders);
  }

  const headers = new Headers(corsHeaders);
  headers.set("Content-Type", "application/json");
  headers.set("Cache-Control", "public, max-age=3600");
  headers.set("ETag", object.httpEtag);

  return new Response(object.body, { status: 200, headers });
}

// MARK: - Events Handlers

async function handleEventsManifest(
  env: Env,
  corsHeaders: Record<string, string>
): Promise<Response> {
  const sql = await getSql(env);
  const rows = (await sql`
    SELECT id, name, latitude, longitude, radius_meters, start_date, end_date,
           location, description, image_url, organizer_signing_key, attendee_count, category
    FROM events
    ORDER BY start_date ASC
  `) as unknown as EventRow[];

  const manifest = {
    version: MANIFEST_VERSION,
    signature: null,
    events: rows.map(rowToManifestEvent),
  };

  const headers = new Headers(corsHeaders);
  headers.set("Content-Type", "application/json");
  headers.set("Cache-Control", "public, max-age=3600");

  return new Response(JSON.stringify(manifest), { status: 200, headers });
}

async function handleEventsList(
  request: Request,
  env: Env,
  corsHeaders: Record<string, string>
): Promise<Response> {
  requireInternalApiKey(request, env);
  const sql = await getSql(env);
  const rows = (await sql`
    SELECT id, name, latitude, longitude, radius_meters, start_date, end_date,
           location, description, image_url, organizer_signing_key, attendee_count, category
    FROM events
    ORDER BY start_date ASC
  `) as unknown as EventRow[];

  return jsonResponse({ events: rows.map(rowToManifestEvent) }, 200, corsHeaders);
}

async function handleEventsCreate(
  request: Request,
  env: Env,
  corsHeaders: Record<string, string>
): Promise<Response> {
  requireInternalApiKey(request, env);
  const input = validateEventInput(await readJsonBody(request));
  const sql = await getSql(env);

  const rows = (await sql`
    INSERT INTO events (
      name, latitude, longitude, radius_meters, start_date, end_date,
      location, description, image_url, organizer_signing_key, attendee_count, category
    )
    VALUES (
      ${input.name}, ${input.latitude}, ${input.longitude}, ${input.radiusMeters},
      ${input.startDate}, ${input.endDate},
      ${input.location ?? null}, ${input.description ?? null}, ${input.imageURL ?? null},
      ${input.organizerSigningKey ?? null}, ${input.attendeeCount ?? 0}, ${input.category ?? null}
    )
    RETURNING id, name, latitude, longitude, radius_meters, start_date, end_date,
              location, description, image_url, organizer_signing_key, attendee_count, category
  `) as unknown as EventRow[];

  if (rows.length === 0) {
    throw new HTTPError(500, "Failed to create event");
  }

  return jsonResponse(rowToManifestEvent(rows[0]), 201, corsHeaders);
}

async function handleEventsUpdate(
  request: Request,
  env: Env,
  eventId: string,
  corsHeaders: Record<string, string>
): Promise<Response> {
  requireInternalApiKey(request, env);
  const input = validateEventInput(await readJsonBody(request));
  const sql = await getSql(env);

  const rows = (await sql`
    UPDATE events
    SET name = ${input.name},
        latitude = ${input.latitude},
        longitude = ${input.longitude},
        radius_meters = ${input.radiusMeters},
        start_date = ${input.startDate},
        end_date = ${input.endDate},
        location = ${input.location ?? null},
        description = ${input.description ?? null},
        image_url = ${input.imageURL ?? null},
        organizer_signing_key = ${input.organizerSigningKey ?? null},
        attendee_count = ${input.attendeeCount ?? 0},
        category = ${input.category ?? null}
    WHERE id = ${eventId}
    RETURNING id, name, latitude, longitude, radius_meters, start_date, end_date,
              location, description, image_url, organizer_signing_key, attendee_count, category
  `) as unknown as EventRow[];

  if (rows.length === 0) {
    throw new HTTPError(404, "Event not found");
  }

  return jsonResponse(rowToManifestEvent(rows[0]), 200, corsHeaders);
}

async function handleEventsDelete(
  request: Request,
  env: Env,
  eventId: string,
  corsHeaders: Record<string, string>
): Promise<Response> {
  requireInternalApiKey(request, env);
  const sql = await getSql(env);

  const rows = (await sql`
    DELETE FROM events WHERE id = ${eventId} RETURNING id
  `) as unknown as Array<{ id: string }>;

  if (rows.length === 0) {
    throw new HTTPError(404, "Event not found");
  }

  return new Response(null, { status: 204, headers: new Headers(corsHeaders) });
}

// MARK: - Events Helpers

function rowToManifestEvent(row: EventRow): Record<string, unknown> {
  return {
    id: row.id,
    name: row.name,
    latitude: row.latitude,
    longitude: row.longitude,
    radiusMeters: row.radius_meters,
    startDate: toIso(row.start_date),
    endDate: toIso(row.end_date),
    organizerSigningKey: row.organizer_signing_key ?? "",
    location: row.location,
    description: row.description,
    imageURL: row.image_url,
    attendeeCount: row.attendee_count ?? 0,
    category: row.category,
  };
}

function toIso(value: string | Date): string {
  return value instanceof Date ? value.toISOString() : value;
}

function validateEventInput(raw: unknown): EventInput {
  if (!raw || typeof raw !== "object") {
    throw new HTTPError(400, "Invalid JSON body");
  }
  const body = raw as Record<string, unknown>;

  const name = requireString(body.name, "name", 255);
  const latitude = requireFiniteNumber(body.latitude, "latitude");
  const longitude = requireFiniteNumber(body.longitude, "longitude");
  const radiusMeters = requireFiniteNumber(body.radiusMeters, "radiusMeters");
  if (latitude < -90 || latitude > 90) throw new HTTPError(400, "latitude must be between -90 and 90");
  if (longitude < -180 || longitude > 180) throw new HTTPError(400, "longitude must be between -180 and 180");
  if (radiusMeters <= 0) throw new HTTPError(400, "radiusMeters must be positive");

  const startDate = requireIsoDate(body.startDate, "startDate");
  const endDate = requireIsoDate(body.endDate, "endDate");
  if (Date.parse(endDate) < Date.parse(startDate)) {
    throw new HTTPError(400, "endDate must be on or after startDate");
  }

  const category = optionalString(body.category, "category", 32);
  if (category !== null && category !== undefined && !ALLOWED_CATEGORIES.has(category)) {
    throw new HTTPError(400, `category must be one of ${[...ALLOWED_CATEGORIES].join(", ")}`);
  }

  const attendeeCount = body.attendeeCount;
  let normalizedAttendeeCount: number | null = null;
  if (attendeeCount !== undefined && attendeeCount !== null) {
    if (typeof attendeeCount !== "number" || !Number.isInteger(attendeeCount) || attendeeCount < 0) {
      throw new HTTPError(400, "attendeeCount must be a non-negative integer");
    }
    normalizedAttendeeCount = attendeeCount;
  }

  return {
    name,
    latitude,
    longitude,
    radiusMeters,
    startDate,
    endDate,
    location: optionalString(body.location, "location", 255),
    description: optionalString(body.description, "description", 10_000),
    imageURL: optionalString(body.imageURL, "imageURL", 512),
    organizerSigningKey: optionalString(body.organizerSigningKey, "organizerSigningKey", 1024),
    attendeeCount: normalizedAttendeeCount,
    category: category ?? null,
  };
}

function requireString(value: unknown, field: string, maxLength: number): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HTTPError(400, `${field} is required`);
  }
  if (value.length > maxLength) {
    throw new HTTPError(400, `${field} exceeds ${maxLength} characters`);
  }
  return value;
}

function optionalString(value: unknown, field: string, maxLength: number): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") {
    throw new HTTPError(400, `${field} must be a string`);
  }
  if (value.length > maxLength) {
    throw new HTTPError(400, `${field} exceeds ${maxLength} characters`);
  }
  return value;
}

function requireFiniteNumber(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new HTTPError(400, `${field} must be a finite number`);
  }
  return value;
}

function requireIsoDate(value: unknown, field: string): string {
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) {
    throw new HTTPError(400, `${field} must be an ISO 8601 timestamp`);
  }
  return value;
}

async function readJsonBody(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    throw new HTTPError(400, "Invalid JSON body");
  }
}

function requireInternalApiKey(request: Request, env: Env): void {
  const configured = env.INTERNAL_API_KEY;
  if (!configured || configured.length === 0) {
    throw new HTTPError(503, "Internal API key not configured");
  }
  const presented = getBearerToken(request.headers.get("Authorization"));
  if (!presented || !timingSafeEquals(presented, configured)) {
    throw new HTTPError(401, "Unauthorized");
  }
}

function timingSafeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

type SqlClient = (strings: TemplateStringsArray, ...values: unknown[]) => Promise<unknown>;

async function getSql(env: Env): Promise<SqlClient> {
  if (!env.DATABASE_URL || env.DATABASE_URL.length === 0) {
    throw new HTTPError(503, "Database not configured");
  }
  const { neon } = await import("@neondatabase/serverless");
  return neon(env.DATABASE_URL) as SqlClient;
}

// MARK: - JWT Verification

class HTTPError extends Error {
  constructor(
    public status: number,
    message: string
  ) {
    super(message);
  }
}

async function validateJWT(request: Request, env: Env): Promise<JWTPayload> {
  const secret = env.JWT_SECRET;
  if (!secret || secret.length === 0) {
    throw new HTTPError(503, "JWT secret not configured");
  }

  const token = getBearerToken(request.headers.get("Authorization"));
  if (!token) {
    throw new HTTPError(401, "Unauthorized");
  }

  const claims = await verifyJWT(token, secret);
  if (!claims) {
    throw new HTTPError(401, "Unauthorized");
  }

  return claims;
}

async function verifyJWT(token: string, secret: string): Promise<JWTPayload | null> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    return null;
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  let header: { alg?: string; typ?: string };
  let payload: Partial<JWTPayload>;
  let signatureBytes: Uint8Array;

  try {
    header = JSON.parse(bytesToUtf8(base64UrlDecode(encodedHeader)));
    payload = JSON.parse(bytesToUtf8(base64UrlDecode(encodedPayload)));
    signatureBytes = base64UrlDecode(encodedSignature);
  } catch {
    return null;
  }

  if (header.alg !== "HS256" || header.typ !== "JWT") {
    return null;
  }

  const key = await importHMACKey(secret, ["verify"]);
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const isValid = await crypto.subtle.verify(
    "HMAC",
    key,
    signatureBytes,
    utf8ToBytes(signingInput)
  );
  if (!isValid) {
    return null;
  }

  if (
    typeof payload.sub !== "string" ||
    typeof payload.npk !== "string" ||
    typeof payload.iat !== "number" ||
    typeof payload.exp !== "number"
  ) {
    return null;
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (payload.exp <= nowSeconds) {
    return null;
  }

  return {
    sub: payload.sub,
    npk: payload.npk,
    iat: payload.iat,
    exp: payload.exp,
  };
}

// MARK: - Helpers

function getBearerToken(header: string | null): string | null {
  if (!header || !header.startsWith("Bearer ")) {
    return null;
  }
  const token = header.slice("Bearer ".length).trim();
  return token.length === 0 ? null : token;
}

function getCorsHeaders(env: Env): Record<string, string> {
  const origin = env.CORS_ORIGIN ?? "*";
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Max-Age": "86400",
  };
}

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
  extraHeaders: Record<string, string> = {}
): Response {
  const headers = new Headers(extraHeaders);
  headers.set("Content-Type", "application/json");
  return new Response(JSON.stringify(body), { status, headers });
}

function base64Decode(encoded: string): Uint8Array {
  const binary = atob(encoded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function base64UrlDecode(input: string): Uint8Array {
  const normalized = input.replace(/-/g, "+").replace(/_/g, "/");
  const padding = normalized.length % 4 === 0 ? "" : "=".repeat(4 - (normalized.length % 4));
  return base64Decode(normalized + padding);
}

function bytesToUtf8(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

function utf8ToBytes(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

async function importHMACKey(secret: string, usages: KeyUsage[]): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    utf8ToBytes(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    usages
  );
}
