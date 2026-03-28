/**
 * VerificationSession Durable Object.
 *
 * One instance per phone number (keyed by SHA-256 hash of phone).
 * Manages rate limiting and verification sessions entirely in memory.
 * Zero persistence — all state lost on eviction (by design).
 */
import {
  OTP_EXPIRY_SECONDS,
  SEND_COOLDOWN_SECONDS,
  MAX_SENDS_PER_HOUR,
  MAX_VERIFY_ATTEMPTS,
  MOCK_VALID_CODE,
  type DOSendRequest,
  type DOCheckRequest,
} from "./types";
import { twilioSendVerification, twilioCheckVerification } from "./twilio";

interface Session {
  verificationID: string;
  phone: string;
  createdAt: number;
  attemptsRemaining: number;
  twilioSid?: string;
}

export class VerificationSession implements DurableObject {
  /** Active verification sessions by verificationID. */
  private sessions: Map<string, Session> = new Map();

  /** Timestamps of recent send requests (for rate limiting). */
  private sendTimestamps: number[] = [];

  constructor(
    private readonly state: DurableObjectState,
    private readonly env: unknown
  ) {}

  async fetch(request: Request): Promise<Response> {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    const body = await request.json() as DOSendRequest | DOCheckRequest;

    if (body.action === "send") {
      return this.handleSend(body as DOSendRequest);
    } else if (body.action === "check") {
      return this.handleCheck(body as DOCheckRequest);
    }

    return new Response("Unknown action", { status: 400 });
  }

  private async handleSend(req: DOSendRequest): Promise<Response> {
    const now = Date.now();

    // Clean up expired sessions.
    this.cleanExpiredSessions(now);

    // Rate limit: 60s cooldown.
    const lastSend = this.sendTimestamps[this.sendTimestamps.length - 1];
    if (lastSend && now - lastSend < SEND_COOLDOWN_SECONDS * 1000) {
      const retryAfter = Math.ceil((SEND_COOLDOWN_SECONDS * 1000 - (now - lastSend)) / 1000);
      return Response.json(
        { error: "Rate limited", retryAfter },
        {
          status: 429,
          headers: { "Retry-After": String(retryAfter) },
        }
      );
    }

    // Rate limit: max 5 per rolling hour.
    const oneHourAgo = now - 3600_000;
    this.sendTimestamps = this.sendTimestamps.filter((t) => t > oneHourAgo);
    if (this.sendTimestamps.length >= MAX_SENDS_PER_HOUR) {
      const oldestInWindow = this.sendTimestamps[0];
      const retryAfter = Math.ceil((oldestInWindow + 3600_000 - now) / 1000);
      return Response.json(
        { error: "Rate limited", retryAfter },
        {
          status: 429,
          headers: { "Retry-After": String(retryAfter) },
        }
      );
    }

    // Generate composite verification ID: "<phoneHash>:<uuid>"
    // The phoneHash prefix lets /check route back to this DO without the phone number.
    const verificationID = `${req.phoneHash}:${crypto.randomUUID()}`;
    let twilioSid: string | undefined;

    // Send via Twilio or mock.
    if (!req.isMock) {
      try {
        const result = await twilioSendVerification(
          req.phone,
          req.twilioAccountSid!,
          req.twilioAuthToken!,
          req.twilioServiceSid!
        );
        twilioSid = result.sid;
      } catch (err) {
        return Response.json(
          { error: "Failed to send verification code" },
          { status: 502 }
        );
      }
    }

    // Record send timestamp and create session.
    this.sendTimestamps.push(now);
    this.sessions.set(verificationID, {
      verificationID,
      phone: req.phone,
      createdAt: now,
      attemptsRemaining: MAX_VERIFY_ATTEMPTS,
      twilioSid,
    });

    return Response.json({
      verificationID,
      expiresIn: OTP_EXPIRY_SECONDS,
    });
  }

  private async handleCheck(req: DOCheckRequest): Promise<Response> {
    const now = Date.now();
    this.cleanExpiredSessions(now);

    const session = this.sessions.get(req.verificationID);
    if (!session) {
      return Response.json({ error: "Invalid or expired verification" }, { status: 400 });
    }

    // Check expiry.
    if (now - session.createdAt > OTP_EXPIRY_SECONDS * 1000) {
      this.sessions.delete(req.verificationID);
      return Response.json({ error: "Verification expired" }, { status: 400 });
    }

    // Check attempt limit.
    if (session.attemptsRemaining <= 0) {
      this.sessions.delete(req.verificationID);
      return Response.json({ error: "Max attempts exceeded" }, { status: 400 });
    }

    session.attemptsRemaining--;

    // Verify code.
    let verified = false;

    if (req.isMock) {
      verified = req.code === MOCK_VALID_CODE;
    } else {
      try {
        const result = await twilioCheckVerification(
          session.phone,
          req.code,
          req.twilioAccountSid!,
          req.twilioAuthToken!,
          req.twilioServiceSid!
        );
        verified = result.status === "approved";
      } catch {
        return Response.json(
          { error: "Failed to verify code" },
          { status: 502 }
        );
      }
    }

    if (verified) {
      // Clean up session after successful verification.
      this.sessions.delete(req.verificationID);

      // Generate an opaque verification token.
      const tokenBytes = new Uint8Array(32);
      crypto.getRandomValues(tokenBytes);
      let token = "";
      for (let i = 0; i < tokenBytes.length; i++) {
        token += tokenBytes[i].toString(16).padStart(2, "0");
      }

      return Response.json({ verified: true, token });
    }

    return Response.json({ verified: false });
  }

  private cleanExpiredSessions(now: number): void {
    for (const [id, session] of this.sessions) {
      if (now - session.createdAt > OTP_EXPIRY_SECONDS * 1000) {
        this.sessions.delete(id);
      }
    }
  }
}
