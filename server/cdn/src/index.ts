/**
 * Blip CDN worker — avatar upload and serving.
 *
 * POST /avatars/upload  — multipart upload (JWT-authenticated)
 * GET  /avatars/:userId.jpg — serve avatar image from R2
 * GET  /manifests/events.json — static event manifest (passthrough)
 * GET  /health — liveness check
 */

export interface Env {
  AVATARS: R2Bucket;
  JWT_SECRET?: string;
  CORS_ORIGIN?: string;
  MAX_AVATAR_BYTES?: string;
}

interface JWTPayload {
  sub: string;
  npk?: string;
  iat: number;
  exp: number;
}

const ACCEPTED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
const DEFAULT_MAX_BYTES = 2 * 1024 * 1024; // 2MB
const AVATAR_CACHE_SECONDS = 3600; // 1hr

function corsHeaders(env?: Env): Record<string, string> {
  const headers: Record<string, string> = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
  };
  const corsOrigin = env?.CORS_ORIGIN;
  if (!corsOrigin) return headers;

  headers["Access-Control-Allow-Origin"] = corsOrigin;
  headers["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS";
  headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization";
  return headers;
}

function json(data: unknown, status = 200, env?: Env): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders(env) },
  });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(env) });
    }

    const url = new URL(request.url);

    try {
      if (url.pathname === "/health") {
        return json({ status: "ok" }, 200, env);
      }

      // Serve avatar
      if (request.method === "GET" && url.pathname.startsWith("/avatars/")) {
        return handleGetAvatar(url, env);
      }

      // Serve event manifests (static passthrough)
      if (request.method === "GET" && url.pathname.startsWith("/manifests/")) {
        return handleGetManifest(url, env);
      }

      // Upload avatar
      if (request.method === "POST" && url.pathname === "/avatars/upload") {
        return handleUploadAvatar(request, env);
      }

      return json({ error: "Not found" }, 404, env);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Internal error";
      const status = error instanceof HTTPError ? error.status : 500;
      console.error(`[cdn] ${url.pathname}: ${message}`);
      return json({ error: message }, status, env);
    }
  },
};

// MARK: - Upload Avatar

async function handleUploadAvatar(request: Request, env: Env): Promise<Response> {
  const auth = await authenticateRequest(request, env);

  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.includes("multipart/form-data")) {
    throw new HTTPError(400, "Expected multipart/form-data");
  }

  const formData = await request.formData();
  const userId = formData.get("userId");
  const file = formData.get("avatar");

  if (!userId || typeof userId !== "string") {
    throw new HTTPError(400, "Missing userId field");
  }

  if (!(file instanceof File)) {
    throw new HTTPError(400, "Missing avatar file");
  }

  // Validate file type
  if (!ACCEPTED_TYPES.has(file.type)) {
    throw new HTTPError(400, `Unsupported image type: ${file.type}. Use JPEG, PNG, or WebP`);
  }

  // Validate file size
  const maxBytes = parseInt(env.MAX_AVATAR_BYTES ?? String(DEFAULT_MAX_BYTES), 10);
  if (file.size > maxBytes) {
    throw new HTTPError(413, `Image too large (max ${Math.floor(maxBytes / 1024 / 1024)}MB)`);
  }

  const imageData = await file.arrayBuffer();

  // Store in R2 as userId.jpg
  const key = `${userId}.jpg`;
  await env.AVATARS.put(key, imageData, {
    httpMetadata: {
      contentType: file.type,
      cacheControl: `public, max-age=${AVATAR_CACHE_SECONDS}`,
    },
    customMetadata: {
      uploadedBy: auth.sub,
      uploadedAt: new Date().toISOString(),
    },
  });

  const avatarURL = new URL(`/avatars/${key}`, request.url).toString();

  return json({ url: avatarURL }, 201, env);
}

// MARK: - Get Avatar

async function handleGetAvatar(url: URL, env: Env): Promise<Response> {
  // Extract userId from /avatars/userId.jpg
  const match = url.pathname.match(/^\/avatars\/([a-zA-Z0-9-]+)\.jpg$/);
  if (!match) {
    throw new HTTPError(404, "Not found");
  }

  const key = `${match[1]}.jpg`;
  const object = await env.AVATARS.get(key);

  if (!object) {
    throw new HTTPError(404, "Avatar not found");
  }

  const headers = new Headers(corsHeaders(env));
  headers.set("Content-Type", object.httpMetadata?.contentType ?? "image/jpeg");
  headers.set("Cache-Control", `public, max-age=${AVATAR_CACHE_SECONDS}`);
  headers.set("ETag", object.httpEtag);

  return new Response(object.body, { headers });
}

// MARK: - Get Manifest (passthrough for existing CDN behavior)

async function handleGetManifest(url: URL, env: Env): Promise<Response> {
  // The existing blip-cdn worker serves static manifests.
  // This preserves that route for backwards compatibility.
  return json({ error: "Manifest not found" }, 404, env);
}

// MARK: - Auth

async function authenticateRequest(request: Request, env: Env): Promise<JWTPayload> {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    throw new HTTPError(401, "Unauthorized");
  }

  const token = authHeader.slice(7);
  if (!token.includes(".")) {
    throw new HTTPError(401, "JWT required for upload");
  }

  const secret = env.JWT_SECRET;
  if (!secret) {
    throw new HTTPError(503, "JWT secret not configured");
  }

  const claims = await verifyJWT(token, secret);
  if (!claims) {
    throw new HTTPError(401, "Invalid or expired token");
  }

  return claims;
}

async function verifyJWT(token: string, secret: string): Promise<JWTPayload | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );

  const signatureInput = encoder.encode(`${parts[0]}.${parts[1]}`);
  const signature = base64UrlDecode(parts[2]);

  const valid = await crypto.subtle.verify("HMAC", key, signature, signatureInput);
  if (!valid) return null;

  const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"))) as JWTPayload;

  if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) {
    return null;
  }

  return payload;
}

function base64UrlDecode(str: string): Uint8Array {
  const base64 = str.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

// MARK: - Errors

class HTTPError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}
