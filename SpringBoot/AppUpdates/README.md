AVA Windows update packages live here.

Workflow:

1. Run `Flutter/bump_version.cmd 0.1.1`.
   - Demo line starts at `0.1.0`.
   - Patch releases should increase like `0.1.1`, `0.1.2`, ... `0.1.37`.
2. Run `Flutter/package_windows_update.cmd`.
3. Set the backend update version to the same version.
   - `AVA_APP_WINDOWS_LATEST_VERSION=0.1.1`
   - `AVA_APP_WINDOWS_FILE_NAME=ava-windows-0.1.1.zip`
4. Restart the backend.

Clients check `/api/app-updates/windows/latest` on app startup. If the server
version is higher than the local app version and the zip exists, the app shows
an update dialog and applies the package after download.
