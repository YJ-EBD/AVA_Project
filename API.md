# AVA API

NodeBackend listens on port `8080` by default.

## Health

- `GET /api/health`
- `GET /rtc/validate`

## Auth

- `POST /api/auth/signup`
- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`
- `GET /api/auth/session`
- `POST /api/auth/verify-password`
- `POST /api/auth/email-verifications`
- `POST /api/auth/email-verifications/confirm`

## Users

- `GET /api/users`
- `GET /api/users/me`
- `PUT /api/users/me/profile`
- `PUT /api/users/me/presence`
- `GET /api/users/company/employees/search`
- `POST /api/users/company/employees`
- `POST /api/users/company/blocked-employees`
- `DELETE /api/users/company/blocked-employees`

## Chat

- `GET /api/chat/rooms`
- `POST /api/chat/direct-rooms`
- `POST /api/chat/group-rooms`
- `POST /api/chat/self-room`
- `GET /api/chat/rooms/{roomCode}/messages`
- `POST /api/chat/rooms/{roomCode}/messages`
- `POST /api/chat/rooms/{roomCode}/attachments`
- `GET /api/chat/rooms/{roomCode}/attachments/{attachmentId}`
- `POST /api/chat/rooms/{roomCode}/read`
- `POST /api/chat/rooms/{roomCode}/messages/{messageId}/delete-for-everyone`

Realtime:

- `/topic/rooms/{roomCode}`
- `/topic/rooms/{roomCode}/typing`
- `/topic/rooms/{roomCode}/read-state`
- `/user/queue/chat-events`
- `/user/queue/mobile-push`

## AZOOM

- `GET /api/azoom/channels`
- `GET /api/azoom/workspace`
- `POST /api/azoom/voice-channels/{channelId}/join`
- `POST /api/azoom/voice-channels/{channelId}/leave`
- `PUT /api/azoom/voice-channels/{channelId}/status`
- `GET /api/azoom/voice-channels/{channelId}/livekit-token`
- `POST /api/azoom/voice-channels/{channelId}/effects/firework`
- `GET /api/azoom/meeting-transcripts`
- `GET /api/azoom/meeting-transcripts/{transcriptId}`
- `POST /api/azoom/voice-channels/{channelId}/notiva/start`
- `POST /api/azoom/voice-channels/{channelId}/notiva/finish`
- `POST /api/azoom/voice-channels/{channelId}/notiva/realtime-audio`
- `POST /api/azoom/voice-channels/{channelId}/notiva/batch-audio`

Realtime:

- `/topic/azoom/voice/{roomName}`
- `/topic/azoom/voice-effects/{roomName}`
- `/topic/azoom/notiva/{roomName}`

Notiva audio can also be smoke-tested directly against `LLM_Server` through `POST /v1/notiva/transcribe-raw?language=ko` or the multipart `/v1/notiva/transcribe` endpoint.

## Calendar

- `GET /api/calendar/events`
- `POST /api/calendar/events`
- `PATCH /api/calendar/events/{id}`
- `DELETE /api/calendar/events/{id}`
- `GET /api/calendar/categories`
- `POST /api/calendar/categories`
- `PATCH /api/calendar/categories/{id}`
- `POST /api/calendar/conflicts/check`
- `POST /api/calendar/availability/suggest`
- `GET /api/calendar/summary/today`
- `GET /api/calendar/summary/week`

## AVA AI

- `GET /api/ai/messages`
- `POST /api/ai/messages`
- `POST /api/ai/messages/reset`
- `GET /api/ai/workspace/files`
- `GET /api/ai/workspace/files/content`
- `GET /api/ai/workspace/files/preview`
- `POST /api/ai/workspace/files`
- `PUT /api/ai/workspace/files`
- `DELETE /api/ai/workspace/files`
- `POST /api/ai/workspace/uploads`
- `POST /api/ai/workspace/send-to-chat`
- `GET /api/ai/calendar/workspace`

## Updates

- `GET /api/app-updates/{platform}/latest?currentVersion=x.y.z`
- `GET /api/app-updates/{platform}/download/{fileName}`

Release packages are served from `NodeBackend/AppUpdates` unless `AVA_APP_UPDATE_DIR` overrides it.
