# AVA API

All protected endpoints require:

```text
Authorization: Bearer <access-token>
```

## Health

- `GET /api/health`
- `GET /api/readiness`

## Auth

- `POST /api/auth/signup`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `GET /api/auth/session`
- `GET /api/auth/find-account?email=...`

Login, signup, and refresh are rate limited by client and path.

## Users

- `GET /api/users/me`
- `PUT /api/users/me/presence`
- `PUT /api/users/me/profile`
- `GET /api/users`
- `GET /api/users/company/employees/search`
- `POST /api/users/company/employees`
- `POST /api/users/company/blocked-employees`
- `DELETE /api/users/company/blocked-employees`
- `GET /api/users/me/chat-folders`
- `PUT /api/users/me/chat-folders`
- `GET /api/users/me/chat-folder-order`
- `PUT /api/users/me/chat-folder-order`
- `GET /api/users/me/quiet-chat-rooms`
- `PUT /api/users/me/quiet-chat-rooms`

## Normal Chat

- `GET /api/chat/rooms`
- `POST /api/chat/direct-rooms`
- `POST /api/chat/group-rooms`
- `POST /api/chat/self-room`
- `GET /api/chat/rooms/{roomCode}/messages?limit=80`
- `GET /api/chat/rooms/{roomCode}/messages/around/{messageId}?before=40&after=40`
- `POST /api/chat/rooms/{roomCode}/messages`
- `POST /api/chat/rooms/{roomCode}/attachments`
- `GET /api/chat/rooms/{roomCode}/attachments/{attachmentId}`
- `GET /api/chat/rooms/{roomCode}/talk-drawer`
- `POST /api/chat/rooms/{roomCode}/read`
- `POST /api/chat/rooms/{roomCode}/leave`
- `PUT /api/chat/rooms/{roomCode}/notice`
- `PUT /api/chat/rooms/{roomCode}/pin`
- `GET /api/chat/mention-notifications?status=all|requested|checked&limit=80`
- `POST /api/chat/mention-notifications/{notificationId}/checked`

WebSocket:

- send: `/app/rooms/{roomCode}/send`
- typing: `/app/rooms/{roomCode}/typing`
- subscribe: `/topic/rooms/**`

## AZOOM

- `GET /api/azoom/channels`
- `GET /api/azoom/workspace`
- `POST /api/azoom/voice-channels`
- `PUT /api/azoom/voice-channels/{channelId}`
- `DELETE /api/azoom/channels/{channelId}`
- `POST /api/azoom/members`
- `GET /api/azoom/voice-channels/{channelId}/state`
- `POST /api/azoom/voice-channels/{channelId}/join`
- `POST /api/azoom/voice-channels/{channelId}/leave`
- `PUT /api/azoom/voice-channels/{channelId}/status`
- `GET /api/azoom/voice-channels/{channelId}/livekit-token`
- `GET /api/azoom/meeting-transcripts`
- `GET /api/azoom/meeting-transcripts/{transcriptId}`
- `POST /api/azoom/voice-channels/{channelId}/notiva/start`
- `POST /api/azoom/voice-channels/{channelId}/notiva/realtime-utterances`
- `POST /api/azoom/voice-channels/{channelId}/notiva/realtime-audio`
- `POST /api/azoom/voice-channels/{channelId}/notiva/batch-audio`
- `POST /api/azoom/voice-channels/{channelId}/notiva/finish`

WebSocket:

- voice: `/topic/azoom/voice/{roomName}`
- Notiva AI: `/topic/azoom/notiva/{roomName}`

Voice channel responses include `startedAt` and `serverNow`. `startedAt` is set when the first participant joins and cleared only after the channel becomes empty. Clients must calculate the visible elapsed time from server time, not from each user's local join time.

Notiva AI meeting transcripts are stored by voice channel and `yyyy:MM:dd (E) - HH:mm:ss` timestamp. `REALTIME` stores participant-separated live utterances; `BATCH_AUDIO` stores whole-audio transcription results from uploaded audio files.
Spring Boot sends stored audio to the local Notiva Whisper server through `POST /v1/notiva/transcribe-raw?language=ko`; the multipart `/v1/notiva/transcribe` endpoint remains available for direct smoke tests.

## AVA_stock

Base prefix: `/api/ava-stock`

Web MVC:

- `GET /stock`
  - AVA_stock 입출고/재고 대시보드 웹 화면
- `GET /stock/admin`
  - 제품 모델/BOM/부품 마스터 운영자 웹 화면

Runtime API:

- `GET /api/ava-stock/home`
- `POST /api/ava-stock/qr/lookup`
- `POST /api/ava-stock/products/receipts`
- `GET /api/ava-stock/products/{productUnitId}`
- `GET /api/ava-stock/products/by-qr/{qrValue}`
- `GET /api/ava-stock/products/{productUnitId}/used-parts`
- `GET /api/ava-stock/products/{productUnitId}/progress`
- `GET /api/ava-stock/products/{productUnitId}/manufacturing/checklist`
- `POST /api/ava-stock/products/{productUnitId}/manufacturing/save`
- `POST /api/ava-stock/products/{productUnitId}/manufacturing/complete`
- `POST /api/ava-stock/products/{productUnitId}/service/start`
- `GET /api/ava-stock/service-cases/{serviceCaseId}/checklist`
- `POST /api/ava-stock/service-cases/{serviceCaseId}/save`
- `POST /api/ava-stock/service-cases/{serviceCaseId}/complete`
- `GET /api/ava-stock/parts/{partId}`
- `GET /api/ava-stock/parts/by-qr/{qrValue}`
- `POST /api/ava-stock/parts/{partId}/purchase`
- `POST /api/ava-stock/parts/{partId}/adjust`
- `GET /api/ava-stock/parts/{partId}/movements`
- `GET /api/ava-stock/parts/inventory`
- `POST /api/ava-stock/shipments`
- `GET /api/ava-stock/shipments`
- `GET /api/ava-stock/shipments/{shipmentId}`
- `GET /api/ava-stock/dashboard/summary`
- `GET /api/ava-stock/dashboard/stock`
- `GET /api/ava-stock/dashboard/recent-shipments`
- `GET /api/ava-stock/dashboard/part-usage`
- `GET /api/ava-stock/dashboard/shipment-history`

Admin master API, requires `ADMIN` or `SUPERUSER`:

- `GET /api/ava-stock/admin/product-models`
- `POST /api/ava-stock/admin/product-models`
- `PUT /api/ava-stock/admin/product-models/{modelId}`
- `GET /api/ava-stock/admin/product-models/{modelId}/bom-versions`
- `POST /api/ava-stock/admin/product-models/{modelId}/bom-versions`
- `PUT /api/ava-stock/admin/bom-versions/{bomVersionId}`
- `GET /api/ava-stock/admin/bom-versions/{bomVersionId}/items`
- `POST /api/ava-stock/admin/bom-versions/{bomVersionId}/items`
- `PUT /api/ava-stock/admin/bom-items/{bomItemId}`
- `DELETE /api/ava-stock/admin/bom-items/{bomItemId}`
- `GET /api/ava-stock/admin/parts`
- `POST /api/ava-stock/admin/parts`
- `PUT /api/ava-stock/admin/parts/{partId}`
- `POST /api/ava-stock/admin/parts/{partId}/qr-codes`

Stock usage is movement-led. Manufacturing and A/S saves calculate target checked quantity minus already-posted quantity, so repeated saves do not double-decrement part stock. Unchecking creates `REVERSAL` movement rows instead of deleting history.

## AVA AI

- `GET /api/ai/messages`
- `POST /api/ai/messages`

## Notifications

- `GET /api/notifications`
- `POST /api/notifications/{id}/read`
- `POST /api/notifications/read-all`

Realtime user queue:

- `/user/queue/notifications`

## Admin

Requires `ADMIN`.

- `GET /api/admin/overview`
- `GET /api/admin/users`
- `PUT /api/admin/users/{userId}`
- `GET /api/admin/settings`
- `PUT /api/admin/settings`
- `GET /api/admin/audit-logs`
- `GET /api/admin/system-logs`

## App Updates

- `GET /api/app-updates/windows/latest`
- `GET /api/app-updates/android/latest`
- `GET /api/app-updates/windows/download/{fileName}`
- `GET /api/app-updates/android/download/{fileName}`

## Error Shape

```json
{
  "timestamp": "2026-05-17T00:00:00Z",
  "status": 400,
  "code": "BAD_REQUEST",
  "message": "Message",
  "path": "/api/example",
  "details": {}
}
```
