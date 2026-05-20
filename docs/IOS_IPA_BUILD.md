# AVA iOS IPA Build

Windows cannot build a real iOS `.ipa` locally because Flutter iOS builds require
Apple's Xcode toolchain. AVA builds iOS through a macOS GitHub Actions runner.

## GitHub Secrets

Add these repository secrets before running `.github/workflows/ios-ipa.yml`.

- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `IOS_BUNDLE_ID`: AVA iOS bundle identifier, for example `com.ava.avaFlutter`.
- `IOS_CERTIFICATE_P12_BASE64`: Base64 encoded iPhone Distribution or Development `.p12`.
- `IOS_CERTIFICATE_PASSWORD`: Password for the `.p12`.
- `IOS_PROVISIONING_PROFILE_BASE64`: Base64 encoded `.mobileprovision`.
- `IOS_KEYCHAIN_PASSWORD`: Temporary CI keychain password.

## Encoding Files

On PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.p12"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("profile.mobileprovision"))
```

## Build

Run the GitHub Actions workflow manually:

1. Go to Actions.
2. Select `Build iOS IPA`.
3. Click `Run workflow`.
4. Set:
   - `version`: current AVA version, for example `0.1.136`
   - `build_number`: current AVA build number, for example `1136`
   - `export_method`: `ad-hoc`, `app-store`, `development`, or `enterprise`

The signed IPA is uploaded as a workflow artifact from:

```text
Flutter/build/ios/ipa/*.ipa
```
