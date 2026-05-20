# AVA Roadmap

## Implemented In Current Codebase

- BCrypt password signup/login/logout/refresh
- JWT access and refresh tokens
- Redis plus database-backed sessions
- Normal messenger room/message/read/attachment APIs
- Messenger WebSocket events
- AZOOM text channel isolation
- AZOOM voice presence and LiveKit token flow
- AVA AI persisted messages and LLM client abstraction
- Admin overview/user management/settings/audit APIs
- Admin panel in Flutter for ADMIN users, including users, app settings, audit logs, and system logs
- User notifications API and realtime user queue
- Standard API error response
- Auth endpoint rate limiting
- Production readiness endpoint and fail-fast validator
- Sanitized system request logs
- Windows/macOS app update manifest endpoints
- Persisted AZOOM workspace, channels, and members

## Required Before Production

- Replace local/default secrets with production environment variables.
- Run PostgreSQL, MongoDB, Redis, LiveKit, and LLM as native services or external managed services.
- Put TLS reverse proxy in front of Spring Boot.
- Configure public LiveKit ICE candidates.
- Add backup and restore runbooks for PostgreSQL, MongoDB, and update packages.
- Decide whether MongoDB remains required for chat history or becomes an optional mirror only.
- Add CI for backend tests and Flutter analyze/tests.

## Future Work

- Fine-grained role-permission enforcement beyond current `ADMIN`/`USER`.
- Dedicated file table and retention policy.
- Payment and subscription domain.
- AVA AI token accounting and model usage ledger.
- OpenAI/Whisper/STT/TTS providers behind the current AI service boundary.
- Full admin pages for settings, audit logs, notification broadcasting, and system health.
