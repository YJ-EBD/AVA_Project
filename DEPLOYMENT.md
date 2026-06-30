# AVA Deployment Guide

## Goal

Internet users can install the Flutter app, log in, and use realtime chat through one public NodeBackend API/WebSocket server.

## Architecture

- Public: NodeBackend API and WebSocket server over HTTPS/WSS or the current public HTTP/WS endpoint.
- Private: PostgreSQL and optional local model services stay on the server/private network.
- App clients connect only to:
  - `https://<api-domain>` or `http://112.166.136.198:8080`
  - `wss://<api-domain>/ws` or `ws://112.166.136.198:8080/ws`

Do not expose `5432` to the public internet.

## Backend Environment

Set these on the production server:

```powershell
AVA_BACKEND_PORT=8080
AVA_POSTGRES_URL=jdbc:postgresql://localhost:5432/ava
AVA_POSTGRES_USER=ava
AVA_POSTGRES_PASSWORD=<use-a-strong-database-password>
AVA_ALLOWED_ORIGINS=https://<api-domain>
AVA_JWT_SECRET=<use-a-long-random-secret>
AVA_APP_UPDATE_DIR=AppUpdates
```

For desktop/mobile Flutter clients, CORS is less important than for browsers, but keep `AVA_ALLOWED_ORIGINS` strict if Flutter Web is shipped.

## Backend Run

```powershell
cd D:\AVA_Project\NodeBackend
npm install --no-audit --no-fund
npm start
```

Or use the project control script:

```powershell
cd D:\AVA_Project
.\ava_server_control.ps1 restart
```

## Reverse Proxy

Put Nginx, Caddy, IIS, or another reverse proxy in front of NodeBackend when TLS is used.

Required behavior:

- Public `https://<api-domain>` proxies to `http://127.0.0.1:8080`.
- Public `wss://<api-domain>/ws` proxies to `ws://127.0.0.1:8080/ws`.
- TLS certificate is installed for the domain.
- WebSocket upgrade headers are preserved.

## Flutter Windows Release

```powershell
cd D:\AVA_Project\Flutter
.\build_windows_release.cmd https://<api-domain> wss://<api-domain>/ws
.\tooling\package_windows_update.ps1
```

## Flutter Android Release

```powershell
cd D:\AVA_Project\Flutter
.\build_android_release.cmd https://<api-domain> wss://<api-domain>/ws apk
```

Complete Android signing before distributing through a store.

## Current Local Ports

- NodeBackend: `8080`
- PostgreSQL: `5432`
- LiveKit signal: `7880`
- LiveKit TCP fallback: `7881`
- Local LLM: `8088`
- Notiva AI: `8091`
