# AVA Architecture

## System

AVA is split into three runtime surfaces:

- Flutter app: desktop and mobile client. It owns local UI state, session persistence, update UX, media controls, and WebSocket subscriptions.
- Spring Boot API: REST API, JWT auth, WebSocket/STOMP broker, update manifest, admin, notifications, chat, AZOOM, and AI orchestration.
- Supporting services: PostgreSQL, MongoDB, Redis, LiveKit-compatible AZOOM media, and optional local LLM server.

Docker is intentionally not part of the AVA workflow.

## Flutter Structure

- `lib/main.dart`: app bootstrap and Riverpod scope.
- `lib/src/app`: router and app shell.
- `lib/src/config`: runtime API, WebSocket, and app version config.
- `lib/src/features/auth`: login, signup, session store, auth controller, forced logout realtime client.
- `lib/src/features/messenger`: normal messenger domain, state, chat room UI, friends/profile UI, side nav.
- `lib/src/features/azoom`: AZOOM text, voice, LiveKit media, screen share source picker, Notiva AI panel, and meeting transcript viewer.
- `lib/src/features/ai`: AVA AI page and API client.
- `lib/src/features/admin`: admin REST client and admin panel embedded for ADMIN users.
- `lib/src/features/update`: Windows/macOS update checker and installer launcher.
- `lib/src/platform`: native window and popup bridge.

State management uses Riverpod providers and notifiers. REST calls use Dio. Realtime uses STOMP over `/ws`.

## Backend Structure

- `auth`: signup/login/refresh/logout, JWT, persisted sessions, duplicate login.
- `user`: accounts, profiles, presence, company employee management.
- `chat`: normal messenger rooms, messages, attachments, read receipts, WebSocket events.
- `azoom`: persisted AZOOM workspace/channels/members, separate text channels, voice state, LiveKit token flow, Notiva AI transcript storage/API, and Whisper transcription bridge.
- `ai`: AVA AI conversations, messages, knowledge memory, LLM client, web search.
- `admin`: operational overview and user management API.
- `notification`: persisted notifications plus user queue events.
- `ops`: app settings, audit logs, and sanitized request system logs.
- `update`: update manifests and update package downloads.
- `config`: security, CORS, rate limiting, WebSocket config, demo data, compatibility SQL.
- `common`: standardized API error response.

## Auth And Authorization

- Passwords are stored with BCrypt.
- Access and refresh tokens are HMAC JWTs.
- Session id is embedded in tokens and validated against Redis, database session rows, or in-memory fallback.
- `ADMIN` and `USER` are the current application roles.
- Admin APIs use Spring method security with `hasRole('ADMIN')`.

## Messaging

Normal messenger chat uses `/api/chat/**` and `/topic/rooms/**`.

AZOOM text chat uses `/api/azoom/**` and `/topic/azoom/**`. It is intentionally isolated from normal chat storage and topics. AZOOM workspaces, channels, and members are persisted in PostgreSQL; transient voice participant state is refreshed by heartbeat and LiveKit media state.

Notiva AI is triggered from the AZOOM voice-room speech-bubble control. Spring Boot stores transcript headers and ordered utterances in PostgreSQL, publishes live transcript updates on `/topic/azoom/notiva/{roomName}`, and sends uploaded audio files to the local Whisper large-v3 service under `LLM_Server` for real-time chunk or batch audio transcription.

## AI

AVA AI persists both user and assistant messages. The LLM call is isolated in `AvaAiLlmClient`, so OpenAI, local LLM, Whisper, STT, and TTS can be added behind the service boundary without changing the controller.

## Operations

- Auth POST endpoints are rate limited per client and path.
- API errors return a stable shape with `timestamp`, `status`, `code`, `message`, `path`, and `details`.
- Admin changes write audit logs.
- User-facing admin changes create notifications.
- `/api/readiness` reports production-readiness blockers when `AVA_RUNTIME_ENVIRONMENT=production`.
- Production startup can fail fast if default secrets, wildcard CORS, unsafe database DDL, or missing update packages are detected.
- Sanitized request logs are persisted to `system_logs` and exposed to ADMIN users.
