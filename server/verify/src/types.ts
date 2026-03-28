/**
 * FestiChat phone verification types and constants.
 */

// --- Env ---

export interface Env {
  PHONE_SESSION: DurableObjectNamespace;
  TWILIO_ACCOUNT_SID: string;
  TWILIO_AUTH_TOKEN: string;
  TWILIO_VERIFY_SERVICE_SID: string;
}

// --- Request / Response shapes (match iOS client) ---

export interface SendRequest {
  phone: string;
}

export interface SendResponse {
  verificationID: string;
  expiresIn: number;
}

export interface CheckRequest {
  verificationID: string;
  code: string;
}

export interface CheckResponse {
  verified: boolean;
  token?: string;
}

// --- Internal DO protocol ---

/** Messages the Worker sends to the DO via fetch. */
export interface DOSendRequest {
  action: "send";
  phone: string;
  phoneHash: string;
  isMock: boolean;
  twilioAccountSid?: string;
  twilioAuthToken?: string;
  twilioServiceSid?: string;
}

export interface DOCheckRequest {
  action: "check";
  verificationID: string;
  code: string;
  isMock: boolean;
  twilioAccountSid?: string;
  twilioAuthToken?: string;
  twilioServiceSid?: string;
}

// --- Constants ---

/** OTP code length. */
export const OTP_LENGTH = 6;

/** OTP expiration in seconds. */
export const OTP_EXPIRY_SECONDS = 300;

/** Cooldown between send requests in seconds. */
export const SEND_COOLDOWN_SECONDS = 60;

/** Max sends per rolling hour. */
export const MAX_SENDS_PER_HOUR = 5;

/** Max verify attempts per verification session. */
export const MAX_VERIFY_ATTEMPTS = 5;

/** Mock code that always passes in mock mode. */
export const MOCK_VALID_CODE = "000000";

// --- Validation ---

/**
 * Validate E.164 phone number format.
 * Must start with +, followed by 7-15 digits.
 */
export function isValidE164(phone: string): boolean {
  if (!phone.startsWith("+")) return false;
  const digits = phone.slice(1);
  if (digits.length < 7 || digits.length > 15) return false;
  return /^\d+$/.test(digits);
}

/**
 * Check if running in mock mode (no real Twilio credentials).
 */
export function isMockMode(accountSid: string | undefined): boolean {
  return !accountSid || accountSid === "mock";
}
