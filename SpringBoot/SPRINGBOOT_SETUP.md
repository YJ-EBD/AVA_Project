# Spring Boot 기본 세팅

## 설치 환경

- Microsoft OpenJDK `21.0.11 LTS`
  - 경로: `C:\Program Files\Microsoft\jdk-21.0.11.10-hotspot`
- Gradle 전역 설치 없이 프로젝트의 `gradlew.bat` 사용
- Docker Desktop Personal 사용

## Docker 무료 사용 기준

Docker Desktop은 Docker Personal 기준으로 개인/교육/비상업 오픈소스/소규모 사업자에게 무료입니다.
소규모 사업자 기준은 직원 250명 미만 AND 연매출 1천만 달러 미만입니다.

## 프로젝트

- Spring Boot `4.0.6`
- Java `21`
- Gradle Groovy DSL
- Group: `com.ava`
- Artifact: `ava-backend`
- Package: `com.ava.backend`

## 주요 의존성

- Spring Web MVC
- Spring WebSocket
- Spring Security
- Spring Validation
- Spring Data JPA
- PostgreSQL Driver
- Spring Data MongoDB
- Spring Data Redis
- Spring Boot Actuator
- Lombok
- DevTools
- Docker Compose Support

## 기본 설정

- `src/main/resources/application.yml`
  - PostgreSQL, MongoDB, Redis 연결 기본값
  - 기본 서버 포트: `8080`
- `compose.yaml`
  - PostgreSQL `5432`
  - MongoDB `27017`
  - Redis `6379`
  - 로컬 개발용 Docker volume 포함
- `/api/health` 헬스 체크 API
- `/actuator/health` Actuator 헬스 체크
- `/ws` STOMP WebSocket endpoint
  - publish prefix: `/app`
  - subscribe prefix: `/topic`, `/queue`
- Security 설정
  - `/api/health`, `/actuator/health`, `/ws/**`, 인증 API 허용
  - 그 외 요청은 인증 필요

## 실행 명령

```powershell
cd D:\AVA_Project\SpringBoot
docker compose up -d
.\gradlew.bat test
.\gradlew.bat bootRun
```

`bootRun` 실행 시 Docker Desktop이 정상 실행 중이어야 합니다.

## 검증

- `.\gradlew.bat test` 통과
- `GET http://localhost:8080/api/health` 응답 확인
