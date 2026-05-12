# Flutter 기본 세팅

## 설치한 것

- Flutter SDK `3.41.9` 설치
  - Dart `3.11.5`
  - 경로: `D:\AVA_Project\.tools\flutter`
- Android SDK Command-line Tools 설치
  - 경로: `D:\AVA_Project\.tools\android-sdk`
  - Android Platform `android-36`
  - Android Build Tools `36.0.0`, `35.0.0`
  - Android Platform Tools `37.0.0`
  - Android NDK `28.2.13676358`
  - CMake `3.22.1`
- Visual Studio Build Tools 2022 설치
  - 버전: `17.14.31`
  - C++ Windows desktop build 구성요소 포함
- 사용자 환경변수 추가
  - `ANDROID_HOME=D:\AVA_Project\.tools\android-sdk`
  - `ANDROID_SDK_ROOT=D:\AVA_Project\.tools\android-sdk`
  - User `Path`에 Flutter/Android SDK 경로 추가

## 생성한 프로젝트

- Flutter 프로젝트명: `ava_flutter`
- Organization: `com.ava`
- 생성 플랫폼:
  - Windows desktop
  - Android
  - iOS
- iOS 빌드는 Windows에서 불가능하므로, 실제 iOS 빌드는 macOS/Xcode 환경에서 진행해야 합니다.

## 추가된 주요 패키지

- `dio`: REST API 통신
- `go_router`: 화면 라우팅
- `flutter_riverpod`: 상태 관리
- `stomp_dart_client`: Spring Boot STOMP WebSocket 연동

`shared_preferences`는 처음에 검토했지만 Windows Developer Mode가 꺼진 상태에서 desktop plugin symlink 오류가 발생해 제외했습니다. 추후 토큰 저장 기능을 붙일 때 Developer Mode를 켠 뒤 다시 추가하는 편이 좋습니다.

## 기본 앱 구조

- `lib/main.dart`
  - `ProviderScope`로 앱 시작
- `lib/src/app/ava_app.dart`
  - Material 3 테마
  - `MaterialApp.router`
- `lib/src/app/router.dart`
  - `go_router` 기본 라우터
- `lib/src/config/app_config.dart`
  - `AVA_API_BASE_URL`
  - `AVA_WS_URL`
- `lib/src/features/home/presentation`
  - 앱 진입점 화면
- `lib/src/features/messenger`
  - 메신저 UI mock data/domain/presentation 분리
  - 좌측 고정 내비게이션
  - 친구 / 채팅 / 더보기 탭
  - 채팅방 1회 클릭 시 목록 선택 표시
  - 채팅방 더블클릭 시 우측 채팅 패널 표시
  - 채팅 패널은 좌측 기존 UI를 유지한 채 오른쪽으로 확장
  - 채팅 패널 닫기 버튼으로 우측 패널 접기
  - 채팅 패널 열림/닫힘에 맞춰 Windows 창 폭 자동 조절
  - Windows 네이티브 타이틀바 제거 및 앱 내부 타이틀바/창 제어 버튼 구현
  - 앱 창 둥근 모서리 및 최소 창 크기 설정

## 실행 명령

새 터미널에서는 아래처럼 실행합니다.

```powershell
cd D:\AVA_Project\Flutter
flutter doctor
flutter analyze
flutter test
flutter run -d windows
```

이미 열려 있던 PowerShell에서 `flutter` 명령을 못 찾는 경우에는 터미널을 새로 열거나, 프로젝트 로컬 실행 스크립트를 사용합니다.

```powershell
cd D:\AVA_Project\Flutter
.\run_windows.cmd
```

다른 Flutter 명령도 로컬 SDK로 실행할 수 있습니다.

```powershell
.\flutter_local.cmd doctor
.\flutter_local.cmd analyze
.\flutter_local.cmd test
```

Spring Boot 주소를 바꾸고 실행할 때:

```powershell
flutter run -d windows `
  --dart-define=AVA_API_BASE_URL=http://localhost:8080 `
  --dart-define=AVA_WS_URL=ws://localhost:8080/ws
```

## 검증 완료

- `flutter doctor -v` 통과
- `flutter analyze` 통과
- `flutter test` 통과
- `flutter build windows --debug` 성공
  - 결과: `build\windows\x64\runner\Debug\ava_flutter.exe`
- `flutter build apk --debug` 성공
  - 결과: `build\app\outputs\flutter-apk\app-debug.apk`
