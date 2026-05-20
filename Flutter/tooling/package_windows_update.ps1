param(
    [string]$Version = "",
    [string]$BackendDir = "..\SpringBoot",
    [string]$ApiBaseUrl = "",
    [string]$WebsocketUrl = ""
)

$ErrorActionPreference = "Stop"

$FlutterDir = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $FlutterDir
$DefaultAvaApiBaseUrl = "http://112.166.136.198:8080"

function Resolve-AvaApiBaseUrl {
    param([string]$Value)

    $resolved = $Value
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        $resolved = $env:AVA_API_BASE_URL
    }
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        $publicHost = $env:AVA_BACKEND_PUBLIC_HOST
        if (-not [string]::IsNullOrWhiteSpace($publicHost)) {
            $port = $env:AVA_BACKEND_PORT
            if ([string]::IsNullOrWhiteSpace($port)) { $port = "8080" }
            $resolved = "http://${publicHost}:$port"
        } else {
            $resolved = $DefaultAvaApiBaseUrl
        }
    }

    $resolved = $resolved.Trim().TrimEnd("/")
    if (-not ($resolved.StartsWith("http://") -or $resolved.StartsWith("https://"))) {
        throw "ApiBaseUrl must start with http:// or https://."
    }
    return $resolved
}

function Resolve-AvaWebsocketUrl {
    param(
        [string]$ApiBaseUrl,
        [string]$Value
    )

    $resolved = $Value
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        $resolved = $env:AVA_WS_URL
    }
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        if ($ApiBaseUrl.StartsWith("https://")) {
            $resolved = "wss://" + $ApiBaseUrl.Substring("https://".Length) + "/ws"
        } elseif ($ApiBaseUrl.StartsWith("http://")) {
            $resolved = "ws://" + $ApiBaseUrl.Substring("http://".Length) + "/ws"
        }
    }
    return $resolved.Trim()
}

function Ensure-WindowsPluginJunctions {
    $dependencyFile = Join-Path $FlutterDir ".flutter-plugins-dependencies"
    if (-not (Test-Path -LiteralPath $dependencyFile)) {
        throw ".flutter-plugins-dependencies was not generated. Run flutter pub get first."
    }

    $dependencies = Get-Content -LiteralPath $dependencyFile -Raw | ConvertFrom-Json
    $windowsPlugins = @($dependencies.plugins.windows)
    if ($windowsPlugins.Count -eq 0) {
        return
    }

    $junctionRoot = Join-Path $FlutterDir "windows\flutter\ephemeral\.plugin_symlinks"
    New-Item -ItemType Directory -Force -Path $junctionRoot | Out-Null

    foreach ($plugin in $windowsPlugins) {
        $name = [string]$plugin.name
        $target = [string]$plugin.path
        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($target)) {
            continue
        }

        $targetPath = Resolve-Path -LiteralPath $target
        $junctionPath = Join-Path $junctionRoot $name
        if (Test-Path -LiteralPath $junctionPath) {
            continue
        }

        New-Item -ItemType Junction -Path $junctionPath -Target $targetPath | Out-Null
    }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:\s*([0-9]+\.[0-9]+\.[0-9]+)" | Select-Object -First 1
    if ($null -eq $versionLine) {
        throw "pubspec.yaml version was not found."
    }
    $Version = $versionLine.Matches[0].Groups[1].Value
}

$ApiBaseUrl = Resolve-AvaApiBaseUrl $ApiBaseUrl
$WebsocketUrl = Resolve-AvaWebsocketUrl $ApiBaseUrl $WebsocketUrl

& ".\flutter_local.cmd" "pub" "get"
if ($LASTEXITCODE -ne 0) {
    throw "Flutter pub get failed."
}

Ensure-WindowsPluginJunctions

$buildArgs = @("build", "windows", "--release", "--no-pub")
$buildArgs += "--dart-define=AVA_API_BASE_URL=$ApiBaseUrl"
$buildArgs += "--dart-define=AVA_WS_URL=$WebsocketUrl"

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
Write-Host "  api:     $ApiBaseUrl"
Write-Host "  ws:      $WebsocketUrl"
Write-Host "  sha256:  $hash"
Write-Host "  bytes:   $size"
Write-Host ""
Write-Host "Server config:"
Write-Host "  AVA_APP_WINDOWS_LATEST_VERSION=$Version"
Write-Host "  AVA_APP_WINDOWS_FILE_NAME=ava-windows-$Version.zip"
