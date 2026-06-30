param(
	[string]$InstallDir = (Join-Path $PSScriptRoot 'LiveKit'),
	[int]$ProxyPort = 8080,
	[switch]$ForceInstall
)

$ErrorActionPreference = 'Stop'

function Import-AvaEnvFile {
	param([string]$Path)
	$values = @{}
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
		$values[$key] = $value
	}
	return $values
}

$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
$exePath = Join-Path $InstallDir 'livekit-server.exe'
$configPath = Join-Path $InstallDir 'azoom-livekit.yaml'
$envPath = Join-Path $InstallDir 'azoom-livekit.env'
$logsDir = Join-Path $InstallDir 'logs'
$pidPath = Join-Path $InstallDir 'azoom-sfu.pid'

& (Join-Path $PSScriptRoot 'install_azoom_sfu.ps1') -InstallDir $InstallDir -ProxyPort $ProxyPort -Force:$ForceInstall

$envValues = Import-AvaEnvFile -Path $envPath
$signalPort = [int]$envValues['AVA_LIVEKIT_SIGNAL_PORT']
if ($signalPort -le 0) {
	$signalPort = 7880
}

if (Test-Path -LiteralPath $pidPath) {
	$oldPid = (Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1)
	if ($oldPid -match '^\d+$') {
		$oldProcess = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
		if ($null -ne $oldProcess) {
			Write-Host "AZOOM SFU is already running. PID: $oldPid"
			Write-Host "LiveKit URL: $($envValues['AVA_LIVEKIT_URL'])"
			return
		}
	}
}

$listener = Get-NetTCPConnection -LocalPort $signalPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $listener) {
	Write-Host "Port $signalPort is already listening by PID $($listener.OwningProcess). Leaving it untouched."
	Write-Host "LiveKit URL expected by backend: $($envValues['AVA_LIVEKIT_URL'])"
	return
}

New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
$stdout = Join-Path $logsDir 'azoom-sfu.out.log'
$stderr = Join-Path $logsDir 'azoom-sfu.err.log'

$process = Start-Process -FilePath $exePath `
	-ArgumentList @('--config', $configPath, '--bind', '0.0.0.0') `
	-WorkingDirectory $InstallDir `
	-RedirectStandardOutput $stdout `
	-RedirectStandardError $stderr `
	-WindowStyle Hidden `
	-PassThru

Set-Content -LiteralPath $pidPath -Value $process.Id -Encoding ASCII
Start-Sleep -Seconds 3

$started = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
if ($null -eq $started) {
	Write-Host 'AZOOM SFU exited during startup.'
	if (Test-Path -LiteralPath $stderr) {
		Get-Content -LiteralPath $stderr -Tail 80
	}
	exit 1
}

Write-Host "AZOOM SFU started. PID: $($process.Id)"
Write-Host "LiveKit URL: $($envValues['AVA_LIVEKIT_URL'])"
Write-Host 'Backend env loaded: AVA_LIVEKIT_URL / AVA_LIVEKIT_API_KEY / AVA_LIVEKIT_API_SECRET'
