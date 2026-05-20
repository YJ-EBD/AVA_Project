param(
	[int]$BackendPort = 8080,
	[switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

function Import-AvaEnvFile {
	param([string]$Path)

	foreach ($line in Get-Content -LiteralPath $Path) {
		$trimmed = $line.Trim()
		if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
			continue
		}
		$index = $trimmed.IndexOf('=')
		if ($index -le 0) {
			continue
		}
		$key = $trimmed.Substring(0, $index).Trim()
		$value = $trimmed.Substring($index + 1).Trim()
		[Environment]::SetEnvironmentVariable($key, $value, 'Process')
	}
}

& (Join-Path $PSScriptRoot 'start_azoom_sfu.ps1') -ProxyPort $BackendPort
Import-AvaEnvFile -Path (Join-Path $PSScriptRoot 'LiveKit\azoom-livekit.env')
$localEnvPath = Join-Path $PSScriptRoot '.env.local'
if (Test-Path -LiteralPath $localEnvPath) {
	Import-AvaEnvFile -Path $localEnvPath
	Write-Host "Loaded local backend env: $localEnvPath"
}

if (-not $NoRestart) {
	$listeners = Get-NetTCPConnection -LocalPort $BackendPort -State Listen -ErrorAction SilentlyContinue
	foreach ($listener in $listeners) {
		$processInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)" -ErrorAction SilentlyContinue
		$commandLine = if ($null -ne $processInfo) { [string]$processInfo.CommandLine } else { '' }
		$name = if ($null -ne $processInfo) { [string]$processInfo.Name } else { '' }
		if ($name -match 'java|gradle' -or $commandLine -match 'gradle|bootRun|ava-backend') {
			Write-Host "Stopping existing backend on port $BackendPort. PID: $($listener.OwningProcess)"
			Stop-Process -Id $listener.OwningProcess -Force
		} else {
			throw "Port $BackendPort is already in use by PID $($listener.OwningProcess). It does not look like AVA backend, so it was not stopped."
		}
	}
}

$logsDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$stdout = Join-Path $logsDir 'bootRun-azoom.out.log'
$stderr = Join-Path $logsDir 'bootRun-azoom.err.log'
$pidPath = Join-Path $logsDir 'bootRun-azoom.pid'

$gradle = Join-Path $PSScriptRoot 'gradlew.bat'
$process = Start-Process -FilePath $gradle `
	-ArgumentList @('bootRun') `
	-WorkingDirectory $PSScriptRoot `
	-RedirectStandardOutput $stdout `
	-RedirectStandardError $stderr `
	-WindowStyle Hidden `
	-PassThru

Set-Content -LiteralPath $pidPath -Value $process.Id -Encoding ASCII
Write-Host "Spring Boot started with AZOOM SFU env. PID: $($process.Id)"
Write-Host "Logs: $stdout"
