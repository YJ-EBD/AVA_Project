AVA update packages live here.

Workflow:

Codex rule: do not use Docker for AVA development, verification, or runtime
work. Do not add compose files, container runtime dependencies, or start Docker
Desktop unless the user explicitly reverses this rule.

Codex rule: only ship a Flutter app update when the change requires a new
distributed client: client code/assets/platform projects changed, bundled
client behavior changed, old clients cannot safely use the new server contract,
or update/release behavior changed. Server-only fixes that current clients can
use through the existing API/WebSocket contract should be deployed by restarting
the server, without bumping the Flutter version or advertising a new app update.

Codex rule: a version bump is not complete until the matching update packages
exist for the platforms being shipped, and their update manifests return
`updateAvailable: true` for the previous released version.

1. Decide whether the change actually requires an app update.
   - If it is server-only and old clients remain compatible, do not bump the
     Flutter version, do not change app update manifests, and do not build app
     packages; deploy/restart the backend and verify the server behavior.
   - If a distributed client must change, continue with the steps below.
2. Bump the Flutter version for the client release.
   - On Windows, run `Flutter/bump_version.cmd 0.1.1`.
   - On macOS, run `Flutter/tooling/bump_version.sh 0.1.1 1001`.
   - Demo line starts at `0.1.0`.
   - Patch releases should increase like `0.1.1`, `0.1.2`, ... `0.1.37`.
   - Pass the build number explicitly when continuing the current scheme, for
     example `Flutter/bump_version.cmd 0.1.3 1003` or
     `Flutter/tooling/bump_version.sh 0.1.3 1003`.
3. Run `Flutter/package_windows_update.cmd`.
   - Confirm `SpringBoot/AppUpdates/ava-windows-<version>.zip` was created.
   - The package script builds clients against the public AVA backend address
     `http://112.166.136.198:8080` by default so PCs on different networks can
     connect. If the server address changes, pass it explicitly, for example
     `Flutter/package_windows_update.cmd -ApiBaseUrl http://112.166.136.198:8080`.
   - Do not ship Windows installers or update zips that were built with the
     Flutter default `http://localhost:8080`; those only work on the server PC.
   - If another PC still cannot reach the backend, open TCP 8080 on the server
     PC with `SpringBoot/allow_ava_backend_firewall.cmd` from an admin prompt.
4. Build and copy the Android release APK for the same version.
   - Run `Flutter/build_android_release.cmd http://112.166.136.198:8080 ws://112.166.136.198:8080/ws apk`.
   - Confirm `Flutter/build/app/outputs/flutter-apk/ava-android-<version>.apk`
     exists.
   - Confirm `SpringBoot/AppUpdates/ava-android-<version>.apk` exists.
   - Android APKs must use the local AVA release signing key, not the debug
     signing key.
5. Build and copy the macOS DMG for the same version when shipping macOS.
   - Run `Flutter/tooling/package_macos_update.sh`.
   - Confirm `SpringBoot/AppUpdates/AVA_Project_<version>_<build>_macOS.dmg`
     exists, or set `AVA_APP_MACOS_FILE_NAME` to the actual DMG name.
   - macOS clients download the DMG and open it; the user must drag
     `ava_flutter.app` into Applications and restart AVA.
6. Build and copy the iOS IPA for the same version when shipping iOS.
   - Confirm `SpringBoot/AppUpdates/ava-ios-<version>.ipa` exists, or set
     `AVA_APP_IOS_FILE_NAME` to the actual IPA name.
   - iOS cannot silently install arbitrary IPA files from inside the app; the
     client opens the update URL externally.
7. Set the backend update version to the same version.
   - `AVA_APP_WINDOWS_LATEST_VERSION=0.1.1`
   - `AVA_APP_WINDOWS_FILE_NAME=ava-windows-0.1.1.zip`
   - `AVA_APP_ANDROID_LATEST_VERSION=0.1.1`
   - `AVA_APP_ANDROID_FILE_NAME=ava-android-0.1.1.apk`
   - `AVA_APP_MACOS_LATEST_VERSION=0.1.1`
   - `AVA_APP_MACOS_BUILD_NUMBER=1001`
   - `AVA_APP_MACOS_FILE_NAME=AVA_Project_0.1.1_1001_macOS.dmg`
   - `AVA_APP_IOS_LATEST_VERSION=0.1.1`
   - `AVA_APP_IOS_FILE_NAME=ava-ios-0.1.1.ipa`
8. Restart the backend.
9. Verify the update API before calling the work done.
   - `GET /api/app-updates/windows/latest?currentVersion=<previous-version>`
     must return `updateAvailable: true`.
   - `GET /api/app-updates/windows/download/ava-windows-<version>.zip` must
     return `200 OK`.
   - `GET /api/app-updates/android/latest?currentVersion=<previous-version>`
     must return `updateAvailable: true`.
   - `GET /api/app-updates/android/download/ava-android-<version>.apk` must
     return `200 OK`.
   - `GET /api/app-updates/macos/latest?currentVersion=<previous-version>`
     must return `updateAvailable: true` when macOS is shipped.
   - `GET /api/app-updates/macos/download/<file-name>.dmg` must return `200 OK`.
   - `GET /api/app-updates/ios/latest?currentVersion=<previous-version>`
     must return `updateAvailable: true` when iOS is shipped.
   - `GET /api/app-updates/ios/download/<file-name>.ipa` must return `200 OK`.

Clients check their platform update endpoint on app startup. If the server
version is higher than the local app version and the package exists, the app
shows the platform update flow after download.
