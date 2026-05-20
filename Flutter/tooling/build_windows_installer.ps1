param(
    [string]$Version = "",
    [string]$ApiBaseUrl = "",
    [string]$WebsocketUrl = "",
    [switch]$SkipBuild
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

if ([string]::IsNullOrWhiteSpace($Version)) {
    $versionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:\s*([0-9]+\.[0-9]+\.[0-9]+)" | Select-Object -First 1
    if ($null -eq $versionLine) {
        throw "pubspec.yaml version was not found."
    }
    $Version = $versionLine.Matches[0].Groups[1].Value
}

if (-not $SkipBuild) {
    $ApiBaseUrl = Resolve-AvaApiBaseUrl $ApiBaseUrl
    $WebsocketUrl = Resolve-AvaWebsocketUrl $ApiBaseUrl $WebsocketUrl
}

if (-not $SkipBuild) {
    $buildArgs = @("build", "windows", "--release")
    $buildArgs += "--dart-define=AVA_API_BASE_URL=$ApiBaseUrl"
    $buildArgs += "--dart-define=AVA_WS_URL=$WebsocketUrl"

    & ".\flutter_local.cmd" @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter Windows release build failed."
    }
}

$releaseDir = Resolve-Path ".\build\windows\x64\runner\Release"
$appExe = Join-Path $releaseDir "ava_flutter.exe"
if (-not (Test-Path -LiteralPath $appExe)) {
    throw "Windows release executable was not found: $appExe"
}

$distDir = Join-Path $FlutterDir "dist\installer"
$payloadDir = Join-Path $distDir "payload"
New-Item -ItemType Directory -Force -Path $distDir | Out-Null
Remove-Item -LiteralPath $payloadDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null

$zipName = "ava-windows-$Version.zip"
$zipPath = Join-Path $payloadDir $zipName
Compress-Archive -Path (Join-Path $releaseDir "*") -DestinationPath $zipPath -Force

$installScriptPath = Join-Path $payloadDir "install_ava.ps1"
$installScript = @"
`$ErrorActionPreference = "Stop"

`$appName = "AVA"
`$processName = "ava_flutter"
`$installDir = Join-Path `$env:LOCALAPPDATA "Programs\AVA"
`$zipPath = Join-Path `$PSScriptRoot "$zipName"
`$exePath = Join-Path `$installDir "ava_flutter.exe"

function New-AvaShortcut {
    param(
        [Parameter(Mandatory = `$true)][string]`$ShortcutPath,
        [Parameter(Mandatory = `$true)][string]`$TargetPath,
        [Parameter(Mandatory = `$true)][string]`$WorkingDirectory,
        [string]`$Arguments = "",
        [string]`$IconLocation = ""
    )

    `$shortcutDirectory = Split-Path -Parent `$ShortcutPath
    New-Item -ItemType Directory -Force -Path `$shortcutDirectory | Out-Null

    `$shell = New-Object -ComObject WScript.Shell
    `$shortcut = `$shell.CreateShortcut(`$ShortcutPath)
    `$shortcut.TargetPath = `$TargetPath
    `$shortcut.WorkingDirectory = `$WorkingDirectory
    `$shortcut.Arguments = `$Arguments
    if (-not [string]::IsNullOrWhiteSpace(`$IconLocation)) {
        `$shortcut.IconLocation = `$IconLocation
    }
    `$shortcut.Save()
}

function Write-AvaUninstaller {
    param([Parameter(Mandatory = `$true)][string]`$Path)

    `$uninstaller = @'
`$ErrorActionPreference = "Stop"
`$installDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$desktopShortcut = Join-Path ([Environment]::GetFolderPath("DesktopDirectory")) "AVA.lnk"
`$startMenuDir = Join-Path ([Environment]::GetFolderPath("Programs")) "AVA"
`$startShortcut = Join-Path `$startMenuDir "AVA.lnk"
`$uninstallShortcut = Join-Path `$startMenuDir "AVA remove.lnk"

Stop-Process -Name "ava_flutter" -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath `$desktopShortcut -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath `$startShortcut -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath `$uninstallShortcut -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath `$startMenuDir -Force -Recurse -ErrorAction SilentlyContinue

`$cleanupPath = Join-Path `$env:TEMP ("ava-uninstall-" + [guid]::NewGuid().ToString("N") + ".ps1")
`$quotedInstallDir = `$installDir.Replace("'", "''")
Set-Content -LiteralPath `$cleanupPath -Encoding UTF8 -Value "Start-Sleep -Milliseconds 500; Remove-Item -LiteralPath '`$quotedInstallDir' -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath '`$cleanupPath' -Force -ErrorAction SilentlyContinue"
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File ```"`$cleanupPath```"" -WindowStyle Hidden
'@

    Set-Content -LiteralPath `$Path -Encoding UTF8 -Value `$uninstaller
}

if (-not (Test-Path -LiteralPath `$zipPath)) {
    throw "Installer payload was not found: `$zipPath"
}

Stop-Process -Name `$processName -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force -Path `$installDir | Out-Null
Get-ChildItem -LiteralPath `$installDir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
Expand-Archive -LiteralPath `$zipPath -DestinationPath `$installDir -Force

if (-not (Test-Path -LiteralPath `$exePath)) {
    throw "Installed executable was not found: `$exePath"
}

`$desktopShortcut = Join-Path ([Environment]::GetFolderPath("DesktopDirectory")) "AVA.lnk"
`$startMenuDir = Join-Path ([Environment]::GetFolderPath("Programs")) "AVA"
`$startShortcut = Join-Path `$startMenuDir "AVA.lnk"
`$uninstallScript = Join-Path `$installDir "uninstall_ava.ps1"
`$uninstallShortcut = Join-Path `$startMenuDir "AVA remove.lnk"

Write-AvaUninstaller -Path `$uninstallScript
New-AvaShortcut -ShortcutPath `$desktopShortcut -TargetPath `$exePath -WorkingDirectory `$installDir -IconLocation `$exePath
New-AvaShortcut -ShortcutPath `$startShortcut -TargetPath `$exePath -WorkingDirectory `$installDir -IconLocation `$exePath
New-AvaShortcut -ShortcutPath `$uninstallShortcut -TargetPath "powershell.exe" -WorkingDirectory `$installDir -Arguments "-NoProfile -ExecutionPolicy Bypass -File ```"`$uninstallScript```"" -IconLocation "powershell.exe"
"@
Set-Content -LiteralPath $installScriptPath -Encoding UTF8 -Value $installScript

$installCommandPath = Join-Path $payloadDir "install_ava.cmd"
$installCommand = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_ava.ps1"
"@
Set-Content -LiteralPath $installCommandPath -Encoding ASCII -Value $installCommand

$setupPath = Join-Path $distDir "AVA-Setup-$Version.exe"
$sedPath = Join-Path $distDir "AVA-Setup-$Version.sed"
Remove-Item -LiteralPath $setupPath -Force -ErrorAction SilentlyContinue

$targetName = $setupPath
$payloadSource = $payloadDir.TrimEnd("\") + "\"
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3

[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$targetName
FriendlyName=AVA Setup $Version
AppLaunched=install_ava.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=install_ava.cmd
UserQuietInstCmd=install_ava.cmd
SourceFiles=SourceFiles

[SourceFiles]
SourceFiles0=$payloadSource

[SourceFiles0]
install_ava.cmd=
install_ava.ps1=
$zipName=
"@
Set-Content -LiteralPath $sedPath -Encoding ASCII -Value $sed

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$iexpress = (Get-Command "iexpress.exe" -ErrorAction Stop).Source
$iexpressProcess = Start-Process -FilePath $iexpress -ArgumentList @("/N", "/Q", $sedPath) -Wait -PassThru
if (-not (Test-Path -LiteralPath $setupPath)) {
    throw "Installer executable was not created: $setupPath (IExpress exit code: $($iexpressProcess.ExitCode))"
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $setupPath).Hash.ToLowerInvariant()
$size = (Get-Item -LiteralPath $setupPath).Length

Write-Host "Created AVA Windows installer:"
Write-Host "  $setupPath"
Write-Host "  version: $Version"
if (-not $SkipBuild) {
    Write-Host "  api:     $ApiBaseUrl"
    Write-Host "  ws:      $WebsocketUrl"
}
Write-Host "  sha256:  $hash"
Write-Host "  bytes:   $size"
Write-Host ""
Write-Host "Install target:"
Write-Host "  %LOCALAPPDATA%\Programs\AVA"

exit 0
