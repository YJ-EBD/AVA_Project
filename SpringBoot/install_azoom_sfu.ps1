param(
	[string]$InstallDir = (Join-Path $PSScriptRoot 'LiveKit'),
	[string]$PublicIp = $env:AVA_LIVEKIT_PUBLIC_IP,
	[string]$ApiKey = $env:AVA_LIVEKIT_API_KEY,
	[string]$ApiSecret = $env:AVA_LIVEKIT_API_SECRET,
	[int]$SignalPort = 7880,
	[int]$ProxyPort = 8080,
	[int]$RtcTcpPort = 7881,
	[int]$RtcUdpStart = 50000,
	[int]$RtcUdpEnd = 50100,
	[int]$TurnUdpPort = 3478,
	[switch]$Force
)

$ErrorActionPreference = 'Stop'

function Read-AvaEnvFile {
	param([string]$Path)

	$values = @{}
	if (-not (Test-Path -LiteralPath $Path)) {
		return $values
	}

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
		$values[$key] = $value
	}
	return $values
}

function New-AvaSecret {
	$bytes = New-Object byte[] 32
	$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
	try {
		$rng.GetBytes($bytes)
	} finally {
		$rng.Dispose()
	}
	return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}

if ([string]::IsNullOrWhiteSpace($PublicIp)) {
	$PublicIp = '112.166.136.198'
}

$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
$exePath = Join-Path $InstallDir 'livekit-server.exe'
$configPath = Join-Path $InstallDir 'azoom-livekit.yaml'
$envPath = Join-Path $InstallDir 'azoom-livekit.env'
$logsDir = Join-Path $InstallDir 'logs'

New-Item -ItemType Directory -Force -Path $InstallDir, $logsDir | Out-Null

$existingEnv = Read-AvaEnvFile -Path $envPath
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
	$ApiKey = if ($existingEnv.ContainsKey('AVA_LIVEKIT_API_KEY')) { $existingEnv['AVA_LIVEKIT_API_KEY'] } else { 'ava-azoom' }
}
if ([string]::IsNullOrWhiteSpace($ApiSecret)) {
	$ApiSecret = if ($existingEnv.ContainsKey('AVA_LIVEKIT_API_SECRET')) { $existingEnv['AVA_LIVEKIT_API_SECRET'] } else { New-AvaSecret }
}

if ($Force -or -not (Test-Path -LiteralPath $exePath)) {
	$releaseUrl = 'https://api.github.com/repos/livekit/livekit/releases/latest'
	Write-Host "Downloading latest LiveKit Windows amd64 release metadata..."
	$release = Invoke-RestMethod -Uri $releaseUrl -Headers @{ 'User-Agent' = 'AVA-AZOOM-SFU-Installer' }
	$asset = $release.assets | Where-Object { $_.name -match 'windows_amd64\.zip$' } | Select-Object -First 1
	if ($null -eq $asset) {
		throw 'Could not find a LiveKit windows_amd64 zip asset in the latest release.'
	}

	$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ava-livekit-' + [Guid]::NewGuid().ToString('N'))
	$tempZip = Join-Path $tempRoot $asset.name
	$tempExtract = Join-Path $tempRoot 'extract'
	New-Item -ItemType Directory -Force -Path $tempRoot, $tempExtract | Out-Null
	try {
		Write-Host "Downloading $($asset.name)..."
		Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempZip -Headers @{ 'User-Agent' = 'AVA-AZOOM-SFU-Installer' }
		Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force
		$downloadedExe = Get-ChildItem -LiteralPath $tempExtract -Recurse -File -Filter 'livekit-server.exe' | Select-Object -First 1
		if ($null -eq $downloadedExe) {
			throw 'The LiveKit archive did not contain livekit-server.exe.'
		}
		Copy-Item -LiteralPath $downloadedExe.FullName -Destination $exePath -Force
	} finally {
		if (Test-Path -LiteralPath $tempRoot) {
			Remove-Item -LiteralPath $tempRoot -Recurse -Force
		}
	}
}

$config = @"
port: $SignalPort

rtc:
  tcp_port: $RtcTcpPort
  port_range_start: $RtcUdpStart
  port_range_end: $RtcUdpEnd
  use_external_ip: false
  node_ip: $PublicIp
  allow_tcp_fallback: true
  stun_servers:
    - stun.l.google.com:19302
    - stun1.l.google.com:19302

turn:
  enabled: true
  udp_port: $TurnUdpPort
  relay_range_start: $RtcUdpStart
  relay_range_end: $RtcUdpEnd

keys:
  ${ApiKey}: $ApiSecret

room:
  max_participants: 100

logging:
  level: info
"@

Set-Content -LiteralPath $configPath -Value $config -Encoding UTF8

$envFile = @"
AVA_LIVEKIT_URL=ws://$PublicIp`:$ProxyPort
AVA_LIVEKIT_API_KEY=$ApiKey
AVA_LIVEKIT_API_SECRET=$ApiSecret
AVA_LIVEKIT_PUBLIC_IP=$PublicIp
AVA_LIVEKIT_SIGNAL_PORT=$SignalPort
AVA_LIVEKIT_SIGNAL_PROXY_ENABLED=true
AVA_LIVEKIT_SIGNAL_PROXY_UPSTREAM_URL=ws://127.0.0.1`:$SignalPort
AVA_LIVEKIT_RTC_TCP_PORT=$RtcTcpPort
AVA_LIVEKIT_RTC_UDP_START=$RtcUdpStart
AVA_LIVEKIT_RTC_UDP_END=$RtcUdpEnd
AVA_LIVEKIT_TURN_UDP_PORT=$TurnUdpPort
"@

Set-Content -LiteralPath $envPath -Value $envFile -Encoding UTF8

Write-Host "AZOOM SFU installed at: $InstallDir"
Write-Host "LiveKit URL exposed through backend: ws://$PublicIp`:$ProxyPort"
Write-Host "Open/forward TCP $SignalPort,$RtcTcpPort and UDP $RtcUdpStart-$RtcUdpEnd,$TurnUdpPort on the server PC/router."
