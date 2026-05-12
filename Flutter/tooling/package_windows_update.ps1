param(
    [string]$Version = "",
    [string]$BackendDir = "..\SpringBoot",
    [string]$ApiBaseUrl = "",
    [string]$WebsocketUrl = ""
)

$ErrorActionPreference = "Stop"

$FlutterDir = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $FlutterDir

if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:\s*([0-9]+\.[0-9]+\.[0-9]+)" | Select-Object -First 1
    if ($null -eq $versionLine) {
        throw "pubspec.yaml version was not found."
    }
    $Version = $versionLine.Matches[0].Groups[1].Value
}

if (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $ApiBaseUrl = $ApiBaseUrl.Trim().TrimEnd("/")
    if ([string]::IsNullOrWhiteSpace($WebsocketUrl)) {
        if ($ApiBaseUrl.StartsWith("https://")) {
            $WebsocketUrl = "wss://" + $ApiBaseUrl.Substring("https://".Length) + "/ws"
        } elseif ($ApiBaseUrl.StartsWith("http://")) {
            $WebsocketUrl = "ws://" + $ApiBaseUrl.Substring("http://".Length) + "/ws"
        } else {
            throw "ApiBaseUrl must start with http:// or https://."
        }
    }
}
if (-not [string]::IsNullOrWhiteSpace($WebsocketUrl)) {
    $WebsocketUrl = $WebsocketUrl.Trim()
}

$buildArgs = @("build", "windows", "--release")
if (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    $buildArgs += "--dart-define=AVA_API_BASE_URL=$ApiBaseUrl"
    $buildArgs += "--dart-define=AVA_WS_URL=$WebsocketUrl"
}

& ".\flutter_local.cmd" @buildArgs
if ($LASTEXITCODE -ne 0) {
    throw "Flutter Windows release build failed."
}

$releaseDir = Resolve-Path ".\build\windows\x64\runner\Release"
$backendPath = Resolve-Path $BackendDir
$updatesDir = Join-Path $backendPath "AppUpdates"
New-Item -ItemType Directory -Force -Path $updatesDir | Out-Null

$zipPath = Join-Path $updatesDir "ava-windows-$Version.zip"
Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath -Force

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $zipPath).Length

Write-Host "Created update package:"
Write-Host "  $zipPath"
Write-Host "  version: $Version"
if (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    Write-Host "  api:     $ApiBaseUrl"
    Write-Host "  ws:      $WebsocketUrl"
}
Write-Host "  sha256:  $hash"
Write-Host "  bytes:   $size"
Write-Host ""
Write-Host "Server config:"
Write-Host "  AVA_APP_WINDOWS_LATEST_VERSION=$Version"
Write-Host "  AVA_APP_WINDOWS_FILE_NAME=ava-windows-$Version.zip"
