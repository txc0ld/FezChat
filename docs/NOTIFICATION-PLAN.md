# Notification Plan: Full Apple Notification Support (HEY1263)

## Context

Push notifications currently work at a basic level: the relay triggers a silent push when a packet is queued for an offline peer, the auth worker sends an APNs alert ("Blip: New message from {senderName}"), and the iOS client wakes up and reconnects WebSocket. Local notifications fire for new messages (when channel is not active) and friend requests.

**What's broken:** Notification action taps (reply, mark read, mute, accept/decline friend) go nowhere because `NotificationServiceDelegate` is never assigned. Tapping a notification body doesn't navigate to the conversation. Badge count is hardcoded to 1. The push title says "Blip" not "HeyBlip". No differentiation between DM/SOS/friend request pushes.

This plan delivers WhatsApp-like notification UX in 6 phases, split into 7 PR-sized tasks.

---

## Phase 1: Fix APNs title + differentiated push bodies (server-side)

### 1A. Fix "Blip" → "HeyBlip" (trivial)
- **File:** `server/auth/src/apns.ts` line 32
- Change `title: 'Blip'` → `title: 'HeyBlip'`

### 1B. Relay passes packet type byte to auth push endpoint
- **File:** `server/relay/src/relay-room.ts`
  - Line 318-320: Extract `const packetTypeByte = data[1]` (type byte is unencrypted header metadata at offset 1 — does NOT break zero-knowledge, same as existing sender/recipient ID reads)
  - Line 320: Pass to `triggerPush(recipientHex, senderHex, packetTypeByte)`
  - Lines 421-447: Add `packetType?: number` param, include in POST body as `pushType`
- **File:** `server/auth/src/index.ts`
  - Lines 1287-1290: Add `pushType?: number` to `InternalPushBody`
  - Lines 1324-1331: Select alert body by type:
    - `0x11` (DM): `"Message from ${senderName}"`
    - `0x60` (friendRequest): `"${senderName} sent you a friend request"`
    - `0x61` (friendAccept): `"${senderName} accepted your friend request"`
    - `0x40` (sosAlert): `"SOS Alert nearby"`
    - Default: `"New message from ${senderName}"`
  - Both sides treat `pushType` as optional for deploy ordering safety

**Complexity:** Small | **Dependencies:** None | **Deploy:** Relay first, then auth

---

## Phase 2: Wire notification action handling (biggest gap)

### 2A. Assign the delegate
- **File:** `Sources/Services/AppCoordinator.swift`
- After `notificationService = NotificationService()` (line 51) or in `configure()`, add: `notificationService.delegate = self`

### 2B. Fix delegate protocol for reply text
- **File:** `Sources/Services/NotificationService.swift`
  - Line 39-41: Add a second method to `NotificationServiceDelegate`:
    ```swift
    func notificationService(_ service: NotificationService, didReceiveReplyText text: String, with userInfo: [String: Any])
    ```
  - Lines 519-531 (`didReceive`): When `response is UNTextInputNotificationResponse`, extract `.userText` and call the reply-text delegate method instead
  - Line 527-529: Change default tap action from `.reply` to a new `.openConversation` case (or separate delegate method `didTapNotification`) — tapping should navigate, not reply

### 2C. Implement NotificationServiceDelegate on AppCoordinator
- **File:** `Sources/Services/AppCoordinator.swift` — new extension:
  - **Reply:** Extract `channelID` from userInfo, send text via `messageService.sendTextMessage()` to that channel. Risk: need a send-by-channelID method that doesn't require activeChannel — verify MessageService API.
  - **Mark Read:** Extract `channelID`, call `chatViewModel.markChannelAsRead()`
  - **Mute:** Extract `channelID`, toggle mute
  - **Accept Friend:** Extract `friendID`, call `messageService.acceptFriendRequest()`
  - **Decline Friend:** Extract `friendID`, call `messageService.declineFriendRequest()`
  - **Respond SOS:** Extract `alertID`, call `sosViewModel.acceptAlert()`

### Risk
Reply-from-notification requires background message sending (~30s iOS budget). WebSocket may need reconnect. Test this path carefully.

**Complexity:** Large | **Dependencies:** None (parallel with Phase 1)

---

## Phase 3: Notification tap → deep link navigation

### 3A. Add routing mechanism on AppCoordinator
- **File:** `Sources/Services/AppCoordinator.swift`
  - Add observable property: `var pendingNotificationNavigation: NotificationDestination?`
  - Define enum: `NotificationDestination { case conversation(UUID), friendRequest(UUID), sosAlert(UUID) }`
  - Set this in the default-tap handler from Phase 2B

### 3B. MainTabView responds to pending navigation
- **File:** `Sources/Views/Tabs/MainTabView.swift`
  - `coordinator` already passed as a property (line 29)
  - Add `.onChange(of: coordinator.pendingNotificationNavigation)` that switches `selectedTab` (line 23) to the correct tab
  - `selectedTab` stays `@State private` — the `.onChange` bridge avoids breaking ownership

### 3C. ChatListView picks up conversation target
- **File:** `Sources/Views/Tabs/ChatsTab/ChatListView.swift`
  - `coordinator` available via `@Environment(AppCoordinator.self)` (line 45)
  - Add `.onChange(of: coordinator.pendingNotificationNavigation)` for `.conversation(channelID)` case
  - Find or create `ConversationPreview` for that channelID, set `selectedConversation` (line 43)
  - Clear `coordinator.pendingNotificationNavigation = nil` after navigation

### Risk
Cold launch timing: if app is killed and user taps notification, `didReceive` fires before `configure()`. Buffer in `pendingNotificationNavigation` and apply in `start()`.

**Complexity:** Medium | **Dependencies:** Phase 2

---

## Phase 4: Badge count + notification cleanup

### 4A. Clear notifications when opening a conversation
- **File:** `Sources/ViewModels/ChatViewModel.swift`
  - After `markChannelAsRead` in `openConversation`, call `notificationService.clearNotifications(forChannel: channel.id)` (method exists at NotificationService line 370-378, never called)

### 4B. Server-side badge tracking
- **File:** `server/auth/src/index.ts`
  - Add `unread_badge_count` column to users table (DB migration)
  - Lines 1330-1331: Atomically increment before push, use returned value as badge
  - Add `/internal/badge-reset` endpoint to zero the count
- **File:** `Sources/Services/AppCoordinator.swift`
  - Lines 682-691: After `setBadgeCount(0)` on app active, also POST to `/internal/badge-reset` (fire-and-forget)

**Complexity:** Small (client cleanup) + Medium (server badge) | **Dependencies:** Phase 1 for server badge

---

## Phase 5: Wire unused notification types

Verified: SOS (`notifySOSNearby`, `notifySOSResolved`) and set time alerts (`scheduleSetTimeAlert`) are already wired. Only two remain:

### 5A. Friend Nearby
- **File:** `Sources/ViewModels/MeshViewModel.swift` (line ~270, `refreshNearbyFriends`)
- Diff previous `nearbyFriends` against new list, call `notificationService.notifyFriendNearby()` for newly appeared friends
- Needs `notificationService` injected into MeshViewModel (not currently injected)

### 5B. Organizer Announcements
- **File:** `Sources/ViewModels/EventsViewModel.swift` (line ~710, `refreshAnnouncements`)
- Track previously seen announcement IDs, call `notificationService.notifyOrgAnnouncement()` for new ones
- `notificationService` likely already available

**Complexity:** Small | **Dependencies:** None

---

## Phase 6: Notification Service Extension (DEFER)

**Recommendation: Skip for now.** Current pushes show "Message from Alice" which is useful. E2E decryption in an NSE requires app groups, shared keychain, key migration, and extension memory limits. Substantial complexity for marginal UX gain. Revisit when richer content previews become a user priority.

---

## Recommended PR order

| PR | Phase | Ticket title | Complexity | Touches |
|----|-------|-------------|-----------|---------|
| 1 | 1A | Fix APNs title to "HeyBlip" | Trivial | `server/auth/src/apns.ts` |
| 2 | 2 | Wire NotificationServiceDelegate and implement notification actions | Large | `AppCoordinator.swift`, `NotificationService.swift` |
| 3 | 1B | Differentiated push bodies by message type | Small | `relay-room.ts`, `index.ts`, `apns.ts` |
| 4 | 3 | Navigate to conversation on notification tap | Medium | `AppCoordinator.swift`, `MainTabView.swift`, `ChatListView.swift`, `NotificationService.swift` |
| 5 | 4A | Clear delivered notifications when reading messages | Small | `ChatViewModel.swift` |
| 6 | 4B | Server-side badge count tracking | Medium | `index.ts`, `AppCoordinator.swift`, DB migration |
| 7 | 5 | Wire friend-nearby and announcement notifications | Small | `MeshViewModel.swift`, `EventsViewModel.swift` |

PRs 1-2 are highest priority (fix broken behavior). PR 4 depends on PR 2. All others are independent.

---

## Key files

| File | Role |
|------|------|
| `Sources/Services/AppCoordinator.swift` | Delegate assignment, action handlers, navigation routing, badge reset |
| `Sources/Services/NotificationService.swift` | Delegate protocol fix, default tap action fix |
| `Sources/Views/Tabs/MainTabView.swift` | Tab switching on notification tap |
| `Sources/Views/Tabs/ChatsTab/ChatListView.swift` | Conversation selection on notification tap |
| `Sources/ViewModels/ChatViewModel.swift` | Clear notifications on conversation open |
| `server/auth/src/apns.ts` | APNs title fix, payload customization |
| `server/auth/src/index.ts` | Push type handling, badge tracking |
| `server/relay/src/relay-room.ts` | Pass packet type byte to push trigger |

## Verification

After full implementation:
1. Send DM while recipient app is backgrounded → push banner says "HeyBlip: Message from Alice" → tap banner → app opens to that conversation
2. Send friend request → push banner says "HeyBlip: Alice sent you a friend request" → swipe → Accept/Decline actions work
3. Reply from notification action → message sends without opening app
4. Open conversation → delivered notifications for that channel clear, badge decrements
5. Kill app, send message, tap notification → app cold-launches directly into correct conversation
6. Badge count matches actual unread count (server-tracked)
