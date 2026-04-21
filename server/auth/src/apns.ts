import { ApnsClient, Notification, Priority, PushType } from '@fivesheepco/cloudflare-apns2';
import * as Sentry from '@sentry/cloudflare';
import type { Env } from './index';

let cachedClient: ApnsClient | null = null;

function getClient(env: Env): ApnsClient {
    if (!cachedClient) {
        const signingKey = atob(env.APNS_PRIVATE_KEY);
        cachedClient = new ApnsClient({
            team: env.APNS_TEAM_ID,
            keyId: env.APNS_KEY_ID,
            signingKey: signingKey,
            defaultTopic: 'au.heyblip.Blip',
            host: env.APNS_ENVIRONMENT === 'production'
                ? 'api.push.apple.com'
                : 'api.sandbox.push.apple.com',
        });
    }
    return cachedClient;
}

export async function sendPush(
    deviceToken: string,
    senderName: string,
    conversationId: string,
    unreadCount: number,
    env: Env,
    alertBody?: string
): Promise<boolean> {
    try {
        const client = getClient(env);
        const notification = new Notification(deviceToken, {
            alert: { title: 'HeyBlip', body: alertBody ?? `New message from ${senderName}` },
            badge: unreadCount,
            sound: 'default',
            contentAvailable: true,
            mutableContent: true,
            threadId: conversationId,
            priority: Priority.immediate,
            type: PushType.alert,
        });
        await client.send(notification);
        return true;
    } catch (error: any) {
        console.error(`APNs send failed for token ${deviceToken.slice(0, 8)}...: ${error}`);
        // The APNS_ENVIRONMENT drift bug (PR #247) silently sent prod tokens
        // to the sandbox host and only showed up in `wrangler tail`. Tagging
        // by environment/status_code/reason so the next regression is one
        // Sentry filter away.
        Sentry.captureMessage(`APNs send failed: ${error?.reason ?? error?.message ?? String(error)}`, {
            level: 'error',
            tags: {
                provider: 'apns',
                'apns.environment': env.APNS_ENVIRONMENT ?? 'unknown',
                'apns.status_code': String(error?.statusCode ?? error?.status ?? 'unknown'),
                'apns.reason': String(error?.reason ?? 'unknown'),
            },
            extra: {
                deviceTokenPrefix: deviceToken.slice(0, 8),
            },
        });
        return false;
    }
}
