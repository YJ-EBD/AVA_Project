# AVA Architecture

## System

AVA is split into three runtime surfaces:

- Flutter app: desktop and mobile client. It owns local UI state, session persistence, update UX, media controls, and WebSocket subscriptions.
- NodeBackend: Express REST API, JWT auth, STOMP/WebSocket broker, update manifests, admin, notifications, chat, calendar, AZOOM, AVA AI gateway, and AVA_stock API.
- Supporting services: PostgreSQL, LiveKit-compatible AZOOM media, and optional local LLM/Whisper servers.

Docker is intentionally not part of the AVA workflow.

## Flutter Structure

- `lib/main.dart`: app bootstrap and Riverpod scope.
- `lib/src/app`: router and app shell.
- `lib/src/config`: runtime API, WebSocket, and app version config.
- `lib/src/features/auth`: login, signup, session store, auth controller, forced logout realtime client.
- `lib/src/features/messenger`: normal messenger domain, state, chat room UI, friends/profile UI, side nav.
- `lib/src/features/azoom`: voice, LiveKit media, screen share source picker, Notiva AI panel, and meeting transcript viewer.
- `lib/src/features/ai`: AVA AI page and API client.
- `lib/src/features/admin`: admin REST client and admin panel embedded for ADMIN users.
- `lib/src/features/update`: platform update checker and installer launcher.

REST calls use Dio. Realtime uses STOMP over `/ws`.

## Backend Structure

- `NodeBackend/src/routes/auth.js`: signup/login/refresh/logout and email verification.
- `NodeBackend/src/routes/users.js`: accounts, profiles, presence, company employee management.
- `NodeBackend/src/routes/chat.js`: normal messenger rooms, messages, attachments, read receipts, and realtime events.
- `NodeBackend/src/routes/azoom.js`: voice channels, LiveKit tokens, effects, Notiva sessions, and transcript events.
- `NodeBackend/src/routes/ai.js`: AVA AI messages, workspace files, calendar snapshot, and Notion-safe responses.
- `NodeBackend/src/routes/calendar.js`: event/category CRUD, attendees, reminders, linked files, Notion, chat, and AZOOM links.
- `NodeBackend/src/routes/admin.js`: operational overview and user/settings/log APIs.
- `NodeBackend/src/routes/appUpdates.js`: update manifests and package downloads.
- `NodeBackend/src/realtime/stompHub.js`: STOMP broker for `/topic/**` and `/user/queue/**`.

## Auth And Authorization

- Passwords are stored with BCrypt-compatible hashes.
- Access and refresh tokens are HMAC JWTs.
- Session id is embedded in tokens and validated against persisted session rows.
- Admin APIs accept `ADMIN` and `SUPERUSER`.

## Messaging

Normal messenger chat uses `/api/chat/**`, `/topic/rooms/{roomCode}`, and per-user `/queue/chat-events`.

Message send persists the record, marks the sender as read, computes unread counts, publishes the room topic, publishes per-user room snapshots, and creates mobile push backlog events asynchronously so the sender does not wait on push persistence.

AZOOM does not own text chat. AZOOM uses `/api/azoom/**`, `/topic/azoom/voice/{roomName}`, `/topic/azoom/voice-effects/{roomName}`, and `/topic/azoom/notiva/{roomName}` for voice state and meeting transcript events.

## AI

AVA AI stores user/assistant message history in PostgreSQL and exposes workspace file operations under `NodeBackend/AiWorkspace`. LLM, Whisper, STT, and TTS can be connected behind this gateway without changing the Flutter client contract.

## Operations

- API errors return `timestamp`, `status`, `code`, `message`, `path`, and `details`.
- Admin changes write audit logs.
- Notifications and mobile push backlog events are delivered through user queues.
- `ava_server_control.ps1` starts/stops NodeBackend, native LiveKit, Notiva AI, and the local LLM service.
