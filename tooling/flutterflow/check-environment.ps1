param()

$ErrorActionPreference = "Stop"

$checks = [ordered]@{}

$flutterFlowExe = "C:\Program Files\FlutterFlow\flutterflow.exe"
$checks["FlutterFlow Desktop"] = if (Test-Path -LiteralPath $flutterFlowExe) {
    $flutterFlowExe
} else {
    "NOT FOUND"
}

$ghExe = "C:\Program Files\GitHub CLI\gh.exe"
if (-not (Test-Path -LiteralPath $ghExe)) {
    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    $ghExe = if ($ghCommand) { $ghCommand.Source } else { "" }
}
$checks["GitHub CLI"] = if ($ghExe -and (Test-Path -LiteralPath $ghExe)) {
    & $ghExe --version | Select-Object -First 1
} else {
    "NOT FOUND"
}

$checks["Git"] = git --version
$checks["Flutter"] = & "$PSScriptRoot\..\..\Flutter\flutter_local.cmd" --version | Select-Object -First 1
$checks["Java"] = cmd.exe /c "java -version 2>&1" | Select-Object -First 1

[pscustomobject]$checks

Write-Host ""
Write-Host "GitHub auth:"
if ($ghExe -and (Test-Path -LiteralPath $ghExe)) {
    & $ghExe auth status
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "GitHub CLI is installed, but you are not signed in yet."
        Write-Host "Run: `"C:\Program Files\GitHub CLI\gh.exe`" auth login"
    }
} else {
    Write-Host "GitHub CLI is not available on PATH yet. Open a new terminal or add C:\Program Files\GitHub CLI to PATH."
}

exit 0
