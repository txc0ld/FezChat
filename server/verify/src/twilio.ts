/**
 * Twilio Verify API client.
 *
 * Sends and checks OTP codes via Twilio's Verify service.
 * In mock mode, these functions are not called.
 */

export interface TwilioSendResult {
  sid: string;
  status: string;
}

export interface TwilioCheckResult {
  status: string; // "approved" or "pending"
}

/**
 * Send a verification code via Twilio Verify.
 */
export async function twilioSendVerification(
  phone: string,
  accountSid: string,
  authToken: string,
  serviceSid: string
): Promise<TwilioSendResult> {
  const url = `https://verify.twilio.com/v2/Services/${serviceSid}/Verifications`;
  const credentials = btoa(`${accountSid}:${authToken}`);

  const body = new URLSearchParams();
  body.set("To", phone);
  body.set("Channel", "sms");

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Basic ${credentials}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Twilio send failed (${response.status}): ${text}`);
  }

  const data = (await response.json()) as { sid: string; status: string };
  return { sid: data.sid, status: data.status };
}

/**
 * Check a verification code via Twilio Verify.
 */
export async function twilioCheckVerification(
  phone: string,
  code: string,
  accountSid: string,
  authToken: string,
  serviceSid: string
): Promise<TwilioCheckResult> {
  const url = `https://verify.twilio.com/v2/Services/${serviceSid}/VerificationCheck`;
  const credentials = btoa(`${accountSid}:${authToken}`);

  const body = new URLSearchParams();
  body.set("To", phone);
  body.set("Code", code);

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Basic ${credentials}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: body.toString(),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Twilio check failed (${response.status}): ${text}`);
  }

  const data = (await response.json()) as { status: string };
  return { status: data.status };
}
