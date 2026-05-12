param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [int]$BuildNumber = 0
)

$ErrorActionPreference = "Stop"

if ($Version -notmatch "^\d+\.\d+\.\d+$") {
    throw "Version must use semantic version format like 0.1.1."
}

$FlutterDir = Resolve-Path (Join-Path $PSScriptRoot "..")
$pubspecPath = Join-Path $FlutterDir "pubspec.yaml"
$appVersionPath = Join-Path $FlutterDir "lib\src\config\app_version.dart"

if ($BuildNumber -le 0) {
    $parts = $Version.Split(".")
    $BuildNumber = ([int]$parts[0] * 1000000) + ([int]$parts[1] * 1000) + [int]$parts[2]
    if ($BuildNumber -le 0) {
        $BuildNumber = 1
    }
}

$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
$pubspec = $pubspec -replace "(?m)^version:\s*.*$", "version: $Version+$BuildNumber"
[System.IO.File]::WriteAllText($pubspecPath, $pubspec, [System.Text.UTF8Encoding]::new($false))

$appVersion = Get-Content -LiteralPath $appVersionPath -Raw
$appVersion = $appVersion -replace "static const name = '[^']+';", "static const name = '$Version';"
$appVersion = $appVersion -replace "static const buildNumber = \d+;", "static const buildNumber = $BuildNumber;"
[System.IO.File]::WriteAllText($appVersionPath, $appVersion, [System.Text.UTF8Encoding]::new($false))

Write-Host "AVA Flutter version bumped to $Version+$BuildNumber"
