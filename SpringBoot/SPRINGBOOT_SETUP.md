# Spring Boot Setup

## Project Rule

- Do not use Docker for AVA development, verification, or runtime work.
- Do not add compose files or container runtime dependencies to this project.
- PostgreSQL, MongoDB, Redis, LLM, and AZOOM media services must be provided as local/native Windows services, standalone binaries, or external endpoints.

## Runtime

- Java 21
- Spring Boot
- PostgreSQL: `localhost:5432` by default, override with `AVA_POSTGRES_URL`
- MongoDB: `localhost:27017` by default, override with `AVA_MONGODB_URI`
- Redis: `localhost:6379` by default, override with `AVA_REDIS_HOST` and `AVA_REDIS_PORT`
- Backend: `0.0.0.0:8080` by default

## AZOOM Media

AZOOM text chat is separate from the normal messenger chat. Store and publish it
through AZOOM-only DB tables and `/topic/azoom/**`; do not route it through the
normal `채팅` room/message API or `/topic/rooms/**`.

AZOOM voice/video uses LiveKit-compatible WebRTC clients, but the media server
must be a native Windows executable, Windows service, or external server. It
must work from computers on different internet networks, not only the local LAN:

```powershell
cd D:\AVA_Project\SpringBoot
.\start_azoom_sfu.ps1
.\start_backend_with_azoom_sfu.ps1
```

The native SFU installer creates `SpringBoot\LiveKit\azoom-livekit.env` with:

```powershell
AVA_LIVEKIT_URL=ws://112.166.136.198:7880
AVA_LIVEKIT_API_KEY=ava-azoom
AVA_LIVEKIT_API_SECRET=<generated-secret>
```

For external clients, open or forward TCP `7880`, TCP `7881`, and UDP
`50000-50100` plus UDP `3478` to the server PC. LiveKit must advertise public ICE
candidates for `112.166.136.198`; if the LiveKit variables are empty, Spring Boot
keeps AZOOM text chat and voice presence working, but disables actual media token
responses.

## Commands

```powershell
cd D:\AVA_Project\SpringBoot
.\gradlew.bat test
.\gradlew.bat bootRun
.\start_backend_with_azoom_sfu.ps1
```

## Seeded System Account

- `admin@ava.admin` / `Ava1234!` (`SUPERUSER`)
