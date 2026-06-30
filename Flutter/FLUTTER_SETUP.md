# Flutter Setup

## Installed Tooling

- Flutter SDK under `D:\AVA_Project\.tools\flutter`
- Android SDK under `D:\AVA_Project\.tools\android-sdk`
- Visual Studio Build Tools 2022 for Windows desktop builds

## Main Packages

- `dio`: REST API communication
- `go_router`: routing
- `flutter_riverpod`: state management
- `stomp_dart_client`: NodeBackend STOMP WebSocket communication

## Run

```powershell
cd D:\AVA_Project\Flutter
.\flutter_local.cmd pub get
.\flutter_local.cmd analyze
.\flutter_local.cmd test
.\flutter_local.cmd run -d windows
```

To override backend addresses:

```powershell
.\flutter_local.cmd run -d windows `
  --dart-define=AVA_API_BASE_URL=http://localhost:8080 `
  --dart-define=AVA_WS_URL=ws://localhost:8080/ws
```

Windows release packaging copies update ZIPs into `NodeBackend/AppUpdates` by default. macOS packaging does the same from the Mac build machine.
