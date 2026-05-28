param(
    [string]$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$dependenciesPath = Join-Path $ProjectDir '.flutter-plugins-dependencies'
if (-not (Test-Path -LiteralPath $dependenciesPath)) {
    throw "Missing .flutter-plugins-dependencies. Run flutter pub get first."
}

$dependencies = Get-Content -LiteralPath $dependenciesPath -Raw | ConvertFrom-Json
$windowsPlugins = @($dependencies.plugins.windows)
if ($windowsPlugins.Count -eq 0) {
    return
}

$pluginRoot = Join-Path $ProjectDir 'windows\flutter\ephemeral\.plugin_symlinks'
New-Item -ItemType Directory -Force -Path $pluginRoot | Out-Null

foreach ($plugin in $windowsPlugins) {
    $name = [string]$plugin.name
    $target = ([string]$plugin.path).TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($target)) {
        continue
    }

    $junctionPath = Join-Path $pluginRoot $name
    if (Test-Path -LiteralPath $junctionPath) {
        continue
    }

    New-Item -ItemType Junction -Path $junctionPath -Target $target | Out-Null
    Write-Host "Created Windows plugin junction: $name"
}
