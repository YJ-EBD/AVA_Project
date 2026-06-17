# AVA Project

AVA is an internal desktop messenger, AZOOM collaboration space, and AVA AI client.

## Current Stack

- Flutter client: Windows, macOS, Android, iOS skeletons
- Spring Boot backend: REST, WebSocket/STOMP, security, JPA, MongoDB, Redis
- PostgreSQL: relational accounts, profiles, rooms, messages, AZOOM text, AI, admin, notifications, audit logs
- MongoDB: optional normal messenger message mirror/history path
- Redis: current-login/session acceleration, with database-backed session fallback
- LiveKit-compatible AZOOM media: external or native service, not Docker
- Local LLM bridge: `LLM_Server`, including Notiva AI Whisper large-v3 server for AZOOM meeting minutes

## Main Features

- Auth: signup, login, refresh, logout, duplicate-login handling, JWT access/refresh tokens
- Users and profiles: profile update, presence, company user list, employee add/block flows
- Messenger chat: rooms, direct/group/self rooms, messages, attachments, read receipts, notices, pinning, WebSocket realtime
- AZOOM: persisted workspace/voice channels/members, voice presence, LiveKit token flow, screen share/camera client UI, Notiva AI live/batch meeting transcripts
- AVA AI: per-user conversation, persisted user/assistant messages, local LLM abstraction, web-search support
- Admin: overview, user role/enabled management, app settings, audit/system log list, Flutter admin panel
- Notifications: persisted user notifications and user WebSocket delivery
- Updates: Windows, Android, macOS, and iOS update manifest/download endpoints
- Operations: readiness endpoint, auth rate limiting, production config fail-fast checks

## Important Rules

- Do not use Docker for AVA development or verification.
- AZOOM text chat channels are removed; keep AZOOM focused on voice, Notiva AI, and meeting transcripts.
- Only changes that require a new distributed client should bump the Flutter version and ship update packages; server-only compatible fixes should be deployed on the backend without forcing an app update.
- All release packages must use public backend URL `http://112.166.136.198:8080` and WebSocket URL `ws://112.166.136.198:8080/ws`.
- Mac, Windows/Android, and server machines collaborate through GitHub `main`; see `DEVELOPMENT_RULES.md` before release work.

## Quick Commands

```powershell
cd SpringBoot
.\gradlew.bat test
```

```powershell
cd Flutter
.\flutter_local.cmd analyze
.\flutter_local.cmd test
```

```powershell
cd LLM_Server
.\install_whisper_large_v3.ps1
.\start_notiva_ai.cmd
.\test_notiva_ai.ps1
```

## Docs

- `ARCHITECTURE.md`
- `DATABASE.md`
- `API.md`
- `ENVIRONMENT.md`
- `DEPLOYMENT.md`
- `ROADMAP.md`
