/**
 * FestiChat phone verification Worker.
 *
 * Entry point: routes requests, validates input, applies CORS,
 * and delegates to per-phone VerificationSession Durable Objects.
 */
import {
  isValidE164,
  isMockMode,
  OTP_LENGTH,
  type Env,
  type SendRequest,
  type CheckRequest,
  type DOSendRequest,
  type DOCheckRequest,
} from "./types";

export { VerificationSession } from "./verification-session";

// --- CORS ---

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function withCors(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(corsHeaders())) {
    headers.set(k, v);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function jsonResponse(body: unknown, status = 200, extraHeaders?: Record<string, string>): Response {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...corsHeaders(),
    ...extraHeaders,
  };
  return new Response(JSON.stringify(body), { status, headers });
}

// --- Helpers ---

/** SHA-256 hex hash of a string. */
export async function sha256Hex(input: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// --- Worker ---

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Handle CORS preflight.
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return jsonResponse({ status: "ok" });
    }

    if (url.pathname === "/v1/verify/send" && request.method === "POST") {
      return withCors(await handleSend(request, env));
    }

    if (url.pathname === "/v1/verify/check" && request.method === "POST") {
      return withCors(await handleCheck(request, env));
    }

    return jsonResponse({ error: "Not found" }, 404);
  },
};

// --- Handlers ---

async function handleSend(request: Request, env: Env): Promise<Response> {
  let body: SendRequest;
  try {
    body = await request.json() as SendRequest;
  } catch {
    return jsonResponse({ error: "Invalid JSON" }, 400);
  }

  if (!body.phone || typeof body.phone !== "string") {
    return jsonResponse({ error: "Missing phone field" }, 400);
  }

  if (!isValidE164(body.phone)) {
    return jsonResponse({ error: "Invalid phone number format" }, 400);
  }

  const mock = isMockMode(env.TWILIO_ACCOUNT_SID);
  const phoneHash = await sha256Hex(body.phone);
  const doId = env.PHONE_SESSION.idFromName(phoneHash);
  const stub = env.PHONE_SESSION.get(doId);

  const doReq: DOSendRequest = {
    action: "send",
    phone: body.phone,
    phoneHash,
    isMock: mock,
    ...(!mock && {
      twilioAccountSid: env.TWILIO_ACCOUNT_SID,
      twilioAuthToken: env.TWILIO_AUTH_TOKEN,
      twilioServiceSid: env.TWILIO_VERIFY_SERVICE_SID,
    }),
  };

  const doResponse = await stub.fetch(new Request("https://do/send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(doReq),
  }));

  // Forward the DO response (including 429 with Retry-After).
  return doResponse;
}

async function handleCheck(request: Request, env: Env): Promise<Response> {
  let body: CheckRequest;
  try {
    body = await request.json() as CheckRequest;
  } catch {
    return jsonResponse({ error: "Invalid JSON" }, 400);
  }

  if (!body.verificationID || typeof body.verificationID !== "string") {
    return jsonResponse({ error: "Missing verificationID" }, 400);
  }

  if (!body.code || typeof body.code !== "string") {
    return jsonResponse({ error: "Missing code" }, 400);
  }

  if (body.code.length !== OTP_LENGTH || !/^\d+$/.test(body.code)) {
    return jsonResponse({ error: "Invalid code format" }, 400);
  }

  // verificationID format: "<phoneHash>:<uuid>" — extract the routing prefix.
  const separatorIndex = body.verificationID.indexOf(":");
  if (separatorIndex === -1) {
    return jsonResponse({ error: "Invalid verificationID" }, 400);
  }

  const phoneHash = body.verificationID.slice(0, separatorIndex);
  const doId = env.PHONE_SESSION.idFromName(phoneHash);
  const stub = env.PHONE_SESSION.get(doId);

  const mock = isMockMode(env.TWILIO_ACCOUNT_SID);
  const doReq: DOCheckRequest = {
    action: "check",
    verificationID: body.verificationID,
    code: body.code,
    isMock: mock,
    ...(!mock && {
      twilioAccountSid: env.TWILIO_ACCOUNT_SID,
      twilioAuthToken: env.TWILIO_AUTH_TOKEN,
      twilioServiceSid: env.TWILIO_VERIFY_SERVICE_SID,
    }),
  };

  const doResponse = await stub.fetch(new Request("https://do/check", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(doReq),
  }));

  return doResponse;
}
