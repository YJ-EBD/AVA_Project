# AVA Deployment Guide

## Goal

Internet users can install the Flutter app, log in, and use realtime chat through one public Spring Boot backend.

## Architecture

- Public: Spring Boot API and WebSocket server over HTTPS/WSS.
- Private: PostgreSQL, MongoDB, and Redis stay on the server/private network.
- App clients connect only to:
  - `https://<api-domain>`
  - `wss://<api-domain>/ws`

Do not expose `5432`, `27017`, or `6379` to the public internet.

## Backend Environment

Set these on the production server:

```powershell
AVA_BACKEND_PORT=8080
AVA_RUNTIME_ENVIRONMENT=production
AVA_PRODUCTION_FAIL_FAST=true
AVA_POSTGRES_URL=jdbc:postgresql://localhost:5432/ava
AVA_POSTGRES_USER=ava
AVA_POSTGRES_PASSWORD=<use-a-strong-database-password>
AVA_MONGODB_URI=mongodb://ava:ava_password@localhost:27017/ava?authSource=admin
AVA_REDIS_HOST=localhost
AVA_REDIS_PORT=6379
AVA_ALLOWED_ORIGINS=https://<api-domain>
AVA_JWT_SECRET=<use-a-long-random-secret>
```

For production, set `spring.jpa.hibernate.ddl-auto=validate` or `none`; do not run with `update`, `create`, or `create-drop`. The backend exposes `GET /api/readiness` and fails fast when `AVA_RUNTIME_ENVIRONMENT=production` and unsafe production settings are detected.

For desktop/mobile Flutter clients, CORS is less important than for browsers, but keep `AVA_ALLOWED_ORIGINS` strict if you also ship Flutter Web.

## Backend Build

```powershell
cd D:\AVA_Project\SpringBoot
.\gradlew.bat clean bootJar
```

The jar will be under:

```text
SpringBoot\build\libs\
```

Run it:

```powershell
java -jar .\build\libs\ava-backend-0.0.1-SNAPSHOT.jar
```

## Reverse Proxy

Put Nginx, Caddy, IIS, or another reverse proxy in front of Spring Boot.

Required behavior:

- Public `https://<api-domain>` proxies to `http://127.0.0.1:8080`.
- Public `wss://<api-domain>/ws` proxies to `ws://127.0.0.1:8080/ws`.
- TLS certificate is installed for the domain.
- WebSocket upgrade headers are preserved.

An Nginx example is available at:

```text
deploy\nginx\ava.conf.example
```

## Flutter Windows Release

Build with the public backend URL:

```powershell
cd D:\AVA_Project\Flutter
.\build_windows_release.cmd https://<api-domain> wss://<api-domain>/ws
```

Release output:

```text
Flutter\build\windows\x64\runner\Release
```

Package that folder with an installer or zip for users.

## Flutter Android Release

```powershell
cd D:\AVA_Project\Flutter
.\build_android_release.cmd https://<api-domain> wss://<api-domain>/ws apk
```

For store distribution, use:

```powershell
.\build_android_release.cmd https://<api-domain> wss://<api-domain>/ws appbundle
```

Complete Android signing before distributing through a store.

## Current Local Ports

- Spring Boot: `8080`
- PostgreSQL: `5432`
- MongoDB: `27017`
- Redis: `6379`
