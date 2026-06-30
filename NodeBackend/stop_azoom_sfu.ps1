param(
	[string]$InstallDir = (Join-Path $PSScriptRoot 'LiveKit')
)

$ErrorActionPreference = 'Stop'

$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
$pidPath = Join-Path $InstallDir 'azoom-sfu.pid'

if (-not (Test-Path -LiteralPath $pidPath)) {
	Write-Host 'AZOOM SFU PID file was not found.'
	exit 0
}

$pidValue = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pidValue -notmatch '^\d+$') {
	Remove-Item -LiteralPath $pidPath -Force
	Write-Host 'AZOOM SFU PID file was invalid and has been removed.'
	exit 0
}

$process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
if ($null -eq $process) {
	Remove-Item -LiteralPath $pidPath -Force
	Write-Host 'AZOOM SFU was not running.'
	exit 0
}

Stop-Process -Id $process.Id -Force
Remove-Item -LiteralPath $pidPath -Force
Write-Host "AZOOM SFU stopped. PID: $pidValue"
