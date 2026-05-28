# AVA Development Rules

These rules are persistent working rules for Codex on this project.

- Do not use Docker for AVA development, verification, or runtime work.
- Do not add new compose files, container runtimes, or desktop container dependencies unless the user explicitly reverses this rule.
- Do not start Docker Desktop during verification or use it as a hidden dependency.
- For services that need separate runtime processes, use already installed local/native services, Windows services, standalone binaries, or externally configured endpoints.
- AZOOM SFU/media must run as a native LiveKit executable, Windows service, or external server. Keep `SpringBoot/LiveKit/` runtime artifacts out of git.
- AVA/AZOOM must work from computers on different internet networks, not only the local LAN. Build packages and runtime config must use the public backend/media addresses, and AZOOM media must advertise public ICE candidates.
- AZOOM no longer provides text chat channels. Keep normal messenger chat in the `채팅` product, and keep AZOOM focused on voice channels, Notiva AI, and meeting transcripts.
- When implementing a requested change, identify the exact requested UI/logic surface and keep every unrelated UI and behavior untouched. Do not refactor, redesign, or adjust neighboring features unless the user explicitly asks for that specific area.
- After any implemented change that affects user-visible behavior, client/server compatibility, runtime connectivity, media, login, messaging, updates, or distributed app behavior, bump the AVA Flutter version in the same work before calling the task done.
- After a version bump, create both matching app deliverables before calling the task done: the Windows update package and the Android release APK.
- Do not leave the backend latest update version equal to the just-built local client version after user-visible changes; publish the next version package, update both Windows/Android manifest defaults, restart the backend, and verify the previous version reports `updateAvailable: true`.
- The Android release APK must be built from the same Flutter version and copied/named as `Flutter/build/app/outputs/flutter-apk/ava-android-{version}.apk`.
- Android release APKs must always be built with the AVA release signing config from `Flutter/android/key.properties`; never ship an APK signed with the Android debug certificate.
- Android release signing files such as `Flutter/android/key.properties` and `Flutter/android/app/ava-release.jks` are local secrets and must stay ignored by git.
- Do not add `REQUEST_INSTALL_PACKAGES` back to the Android manifest for AVA mobile updates. Mobile updates download the APK to `Downloads/AVA`, then the user installs it from the downloaded file.
- Mobile updates are mandatory release behavior: every Android app build must keep the startup/resume update check enabled and must point to the Android update manifest/APK, just like Windows points to the Windows update package.
- After an Android release APK is shipped, do not replace or delete the local Android release signing key; future APK updates must be signed with the same certificate.
- Windows update packages and Android APKs must be built against the public backend URL `http://112.166.136.198:8080`, not `localhost`, so other PCs and phones can connect.
- The backend update manifest must only be moved to a version after the matching Windows zip exists. If an Android update manifest is added later, it must likewise only point to a version after the matching APK exists.
- On Windows machines where Flutter symlink creation is unavailable, desktop run/build scripts must run `flutter pub get`, then `Flutter/tooling/ensure_windows_plugin_junctions.ps1`, then Flutter with `--no-pub`. Do not call raw `flutter run -d windows` or raw `flutter build windows` in that environment because it can delete plugin junctions and fail before the desktop app opens.
- After every implementation or modification, commit the matching project/version changes, pull/rebase from GitHub, push to GitHub, and verify `git status --short` is empty so VS Code Source Control is empty before reporting completion.
- If VS Code Source Control is not empty, clear it without damaging `AVA_PROJECT`: commit intended source/config/test/documentation changes, keep local secrets and runtime build artifacts ignored, and never use destructive reset/checkout/delete operations against user work.
