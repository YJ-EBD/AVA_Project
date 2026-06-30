# AVA Project

AVA is an internal desktop/mobile messenger, AZOOM collaboration space, AVA AI client, and update distribution server.

## Current Stack

- Flutter client: Windows, macOS, Android, and iOS targets.
- NodeBackend: Express REST API, STOMP WebSocket broker, JWT auth, realtime chat, admin, notifications, app updates, AZOOM, calendar, AVA AI gateway, and AVA_stock API.
- PostgreSQL: accounts, profiles, sessions, chat, notifications, audit logs, calendar, AZOOM transcripts, and AI messages.
- LiveKit-compatible AZOOM media: native executable, Windows service, or external server.
- Local LLM bridge: `LLM_Server`, including the Notiva AI Whisper large-v3 server for AZOOM meeting minutes.

## Main Features

- Auth: signup, login, refresh, logout, duplicate-login handling, JWT access/refresh tokens.
- Users and profiles: profile update, presence, company user list, employee add/block flows.
- Messenger chat: direct/group/self rooms, messages, attachments, read receipts, notices, pinning, and realtime WebSocket events.
- AZOOM: workspace/voice channels, voice presence, LiveKit token flow, screen share/camera client UI, and Notiva AI transcript storage.
- AVA AI: per-user conversation history, workspace file API, Notion-safe fallback responses, and local LLM handoff point.
- Admin: overview, user role/enabled management, app settings, audit/system log list, and Flutter admin panel.
- Updates: Windows, Android, macOS, and iOS update manifest/download endpoints from `NodeBackend/AppUpdates`.

## Important Rules

- Do not use Docker for AVA development or verification.
- AZOOM text chat channels are removed; keep AZOOM focused on voice, Notiva AI, and meeting transcripts.
- Only changes that require a new distributed client should bump the Flutter version and ship update packages. Server-only compatible fixes must be deployed on NodeBackend without forcing an app update.
- Release packages must use public backend URL `http://112.166.136.198:8080` and WebSocket URL `ws://112.166.136.198:8080/ws`.
- Mac, Windows/Android, and server machines collaborate through GitHub `main`; see `DEVELOPMENT_RULES.md` before release work.

## Quick Commands

```powershell
cd NodeBackend
npm install
npm test -- --help
npm run test:chat
npm start
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
- `DEVELOPMENT_RULES.md`
