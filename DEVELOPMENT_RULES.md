# AVA Development Rules

These rules are persistent working rules for Codex on this project.

- Do not use Docker for AVA development, verification, or runtime work.
- Do not add new compose files, container runtimes, or desktop container dependencies unless the user explicitly reverses this rule.
- Do not start Docker Desktop during verification or use it as a hidden dependency.
- For services that need separate runtime processes, use already installed local/native services, Windows services, standalone binaries, or externally configured endpoints.
- AZOOM SFU/media must run as a native LiveKit executable, Windows service, or external server. Keep `SpringBoot/LiveKit/` runtime artifacts out of git.
- AVA/AZOOM must work from computers on different internet networks, not only the local LAN. Build packages and runtime config must use the public backend/media addresses, and AZOOM media must advertise public ICE candidates.
- AZOOM chat and normal messenger chat are separate products inside the company scope. Do not store, publish, subscribe, or list AZOOM chat through the normal `채팅` room/message API or `/topic/rooms/**`; AZOOM uses its own DB/table and `/topic/azoom/**` topics.
- After any implemented change that affects user-visible behavior, client/server compatibility, runtime connectivity, media, login, messaging, updates, or distributed app behavior, bump the AVA Flutter version in the same work before calling the task done.
- After a version bump, create both matching app deliverables before calling the task done: the Windows update package and the Android release APK.
- The Android release APK must be built from the same Flutter version and copied/named as `Flutter/build/app/outputs/flutter-apk/ava-android-{version}.apk`.
- Android release APKs must always be built with the AVA release signing config from `Flutter/android/key.properties`; never ship an APK signed with the Android debug certificate.
- Android release signing files such as `Flutter/android/key.properties` and `Flutter/android/app/ava-release.jks` are local secrets and must stay ignored by git.
- Do not add `REQUEST_INSTALL_PACKAGES` back to the Android manifest for AVA mobile updates. Mobile updates download the APK to `Downloads/AVA`, then the user installs it from the downloaded file.
- After an Android release APK is shipped, do not replace or delete the local Android release signing key; future APK updates must be signed with the same certificate.
- Windows update packages and Android APKs must be built against the public backend URL `http://112.166.136.198:8080`, not `localhost`, so other PCs and phones can connect.
- The backend update manifest must only be moved to a version after the matching Windows zip exists. If an Android update manifest is added later, it must likewise only point to a version after the matching APK exists.
