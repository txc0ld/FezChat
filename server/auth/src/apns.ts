import { ApnsClient, Notification, Priority, PushType } from '@fivesheepco/cloudflare-apns2';
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
    } catch (error) {
        console.error(`APNs send failed for token ${deviceToken.slice(0, 8)}...: ${error}`);
        return false;
    }
}
