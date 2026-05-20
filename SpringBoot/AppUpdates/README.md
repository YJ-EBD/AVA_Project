AVA Windows update packages live here.

Workflow:

Codex rule: do not use Docker for AVA development, verification, or runtime
work. Do not add compose files, container runtime dependencies, or start Docker
Desktop unless the user explicitly reverses this rule.

Codex rule: after any implemented change that affects user-visible behavior,
client/server compatibility, runtime connectivity, media, login, messaging,
updates, or distributed app behavior, bump the Flutter version in the same
change and keep the backend Windows update version in sync.

Codex rule: a version bump is not complete until the matching Windows update
zip exists and the update manifest returns `updateAvailable: true` for the
previous released version.

1. Run `Flutter/bump_version.cmd 0.1.1`.
   - Demo line starts at `0.1.0`.
   - Patch releases should increase like `0.1.1`, `0.1.2`, ... `0.1.37`.
   - Pass the build number explicitly when continuing the current scheme, for
     example `Flutter/bump_version.cmd 0.1.3 1003`.
2. Run `Flutter/package_windows_update.cmd`.
   - Confirm `SpringBoot/AppUpdates/ava-windows-<version>.zip` was created.
   - The package script builds clients against the public AVA backend address
     `http://112.166.136.198:8080` by default so PCs on different networks can
     connect. If the server address changes, pass it explicitly, for example
     `Flutter/package_windows_update.cmd -ApiBaseUrl http://112.166.136.198:8080`.
   - Do not ship Windows installers or update zips that were built with the
     Flutter default `http://localhost:8080`; those only work on the server PC.
   - If another PC still cannot reach the backend, open TCP 8080 on the server
     PC with `SpringBoot/allow_ava_backend_firewall.cmd` from an admin prompt.
3. Set the backend update version to the same version.
   - `AVA_APP_WINDOWS_LATEST_VERSION=0.1.1`
   - `AVA_APP_WINDOWS_FILE_NAME=ava-windows-0.1.1.zip`
4. Restart the backend.
5. Verify the update API before calling the work done.
   - `GET /api/app-updates/windows/latest?currentVersion=<previous-version>`
     must return `updateAvailable: true`.
   - `GET /api/app-updates/windows/download/ava-windows-<version>.zip` must
     return `200 OK`.

Clients check `/api/app-updates/windows/latest` on app startup. If the server
version is higher than the local app version and the zip exists, the app shows
an update dialog and applies the package after download.
