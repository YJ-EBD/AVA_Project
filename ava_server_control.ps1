param(
	[Parameter(Position = 0)]
	[ValidateSet('start', 'stop', 'restart', 'status')]
	[string]$Action = 'status',
	[switch]$SkipDependencies,
	[switch]$NoWait
)

$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$NodeBackendDir = Join-Path $Root 'NodeBackend'
$LiveKitDir = Join-Path $NodeBackendDir 'LiveKit'
$LlmDir = Join-Path $Root 'LLM_Server'
$LlmLogDir = Join-Path $LlmDir 'logs'
$BackendLogDir = Join-Path $NodeBackendDir 'logs'

$DependencyServices = @('postgresql-x64-16', 'Redis', 'MongoDB')

function Write-Ava {
	param([string]$Message)
	Write-Host "[AVA] $Message"
}

function Write-AvaWarning {
	param([string]$Message)
	Write-Warning "[AVA] $Message"
}

function Test-PortListening {
	param([int]$Port)
	$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
	return $null -ne $listener
}

function Test-AppServersRunning {
	$appPorts = @(7880, 7881, 8080, 8088, 8091)
	foreach ($port in $appPorts) {
		if (-not (Test-PortListening -Port $port)) {
			return $false
		}
	}
	return $true
}

function Test-DependencyServicesRunning {
	if ($SkipDependencies) {
		return $true
	}
	foreach ($serviceName in $DependencyServices) {
		$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
		if ($null -eq $service -or $service.Status -ne 'Running') {
			return $false
		}
	}
	return $true
}

function Test-AllServersRunning {
	return (Test-AppServersRunning) -and (Test-DependencyServicesRunning)
}

function Test-BackendEnvSettingPresent {
	param([string]$Name)
	$value = [Environment]::GetEnvironmentVariable($Name, 'Process')
	if (-not [string]::IsNullOrWhiteSpace($value)) {
		return $true
	}
	$envPaths = @(
		(Join-Path $Root '.env.local'),
		(Join-Path $NodeBackendDir '.env.local')
	)
	foreach ($localEnvPath in $envPaths) {
		if (-not (Test-Path -LiteralPath $localEnvPath)) {
			continue
		}
		foreach ($line in Get-Content -LiteralPath $localEnvPath -ErrorAction SilentlyContinue) {
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
			if ($key -eq $Name -and -not [string]::IsNullOrWhiteSpace($value)) {
				return $true
			}
		}
	}
	return $false
}

function Test-NotionConfigured {
	return Test-BackendEnvSettingPresent -Name 'AVA_NOTION_API_TOKEN'
}

function Test-NotionResearchPageConfigured {
	return Test-BackendEnvSettingPresent -Name 'AVA_NOTION_RESEARCH_PAGE_ID'
}

function Test-NotionDevelopmentStatusConfigured {
	return Test-BackendEnvSettingPresent -Name 'AVA_NOTION_DEVELOPMENT_STATUS_DATABASE_ID'
}

function Warn-MissingBackendIntegrations {
	if (-not (Test-NotionConfigured)) {
		Write-AvaWarning 'AVA_NOTION_API_TOKEN is not configured. Notion workspace features will fail after restart.'
	}
	if (-not (Test-NotionResearchPageConfigured)) {
		Write-AvaWarning 'AVA_NOTION_RESEARCH_PAGE_ID is not configured. Research-lab Notion routing may choose the wrong duplicate database after restart.'
	}
	if (-not (Test-NotionDevelopmentStatusConfigured)) {
		Write-AvaWarning 'AVA_NOTION_DEVELOPMENT_STATUS_DATABASE_ID is not configured. Development-status Notion writes may fall back to search after restart.'
	}
}

function Wait-Port {
	param(
		[string]$Name,
		[int]$Port,
		[int]$TimeoutSeconds = 90
	)
	if ($NoWait) {
		return
	}
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while ((Get-Date) -lt $deadline) {
		if (Test-PortListening -Port $Port) {
			Write-Ava "$Name is listening on port $Port."
			return
		}
		Start-Sleep -Seconds 1
	}
	Write-AvaWarning "$Name did not open port $Port within $TimeoutSeconds seconds."
}

function Wait-HttpReady {
	param(
		[string]$Name,
		[string]$Url,
		[int]$TimeoutSeconds = 120,
		[string]$RejectPattern = ''
	)
	if ($NoWait) {
		return
	}
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while ((Get-Date) -lt $deadline) {
		$response = ''
		try {
			$response = & curl.exe -sS --max-time 8 $Url 2>$null
			if ($LASTEXITCODE -eq 0 -and $response -and ($RejectPattern.Length -eq 0 -or $response -notmatch $RejectPattern)) {
				Write-Ava "$Name is ready."
				return
			}
		} catch {
			# Keep waiting.
		}
		Start-Sleep -Seconds 2
	}
	Write-AvaWarning "$Name did not become HTTP-ready within $TimeoutSeconds seconds."
}

function Get-ProcessCommandLine {
	param([int]$ProcessId)
	return Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
}

function Stop-MatchedProcess {
	param(
		[int]$ProcessId,
		[string]$Name,
		[scriptblock]$Matcher
	)
	$process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
	if ($null -eq $process) {
		return
	}
	$info = Get-ProcessCommandLine -ProcessId $ProcessId
	$matches = & $Matcher $info $process
	if (-not $matches) {
		Write-AvaWarning "Skipping PID $ProcessId for $Name because it does not look like an AVA process."
		return
	}
	Write-Ava "Stopping $Name. PID: $ProcessId"
	Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Stop-PidFileProcess {
	param(
		[string]$PidFile,
		[string]$Name
	)
	if (-not (Test-Path -LiteralPath $PidFile)) {
		return
	}
	$pidValue = Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($pidValue -match '^\d+$') {
		$process = Get-Process -Id ([int]$pidValue) -ErrorAction SilentlyContinue
		if ($null -ne $process) {
			Write-Ava "Stopping $Name from PID file. PID: $pidValue"
			Stop-Process -Id ([int]$pidValue) -Force -ErrorAction SilentlyContinue
		}
	}
	Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
}

function Stop-PortProcesses {
	param(
		[int[]]$Ports,
		[string]$Name,
		[scriptblock]$Matcher
	)
	$owners = @()
	foreach ($port in $Ports) {
		$owners += Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
			Select-Object -ExpandProperty OwningProcess
	}
	foreach ($owner in ($owners | Sort-Object -Unique)) {
		if ($owner -and [int]$owner -gt 0) {
			Stop-MatchedProcess -ProcessId ([int]$owner) -Name $Name -Matcher $Matcher
		}
	}
}

function Test-BackendProcess {
	param($Info, $Process)
	$name = [string]$Process.ProcessName
	$commandLine = if ($null -ne $Info) { [string]$Info.CommandLine } else { '' }
	return $name -match 'node' -or $commandLine -match 'NodeBackend|src[\\/]server\.js'
}

function Test-LiveKitProcess {
	param($Info, $Process)
	$name = [string]$Process.ProcessName
	$commandLine = if ($null -ne $Info) { [string]$Info.CommandLine } else { '' }
	return $name -match 'livekit-server' -or $commandLine -match 'livekit-server|azoom-livekit'
}

function Test-LlmProcess {
	param($Info, $Process)
	$name = [string]$Process.ProcessName
	$commandLine = if ($null -ne $Info) { [string]$Info.CommandLine } else { '' }
	return $name -match 'llama-server|powershell' -or $commandLine -match 'llama-server|Qwen_Qwen3\.5|ava-qwen|--port"?\s+8088'
}

function Test-NotivaProcess {
	param($Info, $Process)
	$name = [string]$Process.ProcessName
	$commandLine = if ($null -ne $Info) { [string]$Info.CommandLine } else { '' }
	return $name -match 'python|powershell|uvicorn' -or $commandLine -match 'notiva_ai_server|uvicorn|--port"?\s+8091'
}

function Stop-DependencyServices {
	if ($SkipDependencies) {
		Write-Ava 'Skipping dependency services.'
		return
	}
	foreach ($serviceName in $DependencyServices) {
		$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
		if ($null -eq $service) {
			Write-AvaWarning "Dependency service not found: $serviceName"
			continue
		}
		if ($service.Status -eq 'Stopped') {
			Write-Ava "$serviceName is already stopped."
			continue
		}
		try {
			Write-Ava "Stopping dependency service: $serviceName"
			Stop-Service -Name $serviceName -Force -ErrorAction Stop
			(Get-Service -Name $serviceName).WaitForStatus('Stopped', '00:00:45')
		} catch {
			Write-AvaWarning "Could not stop $serviceName. Run the terminal as Administrator if you need to control Windows services. $($_.Exception.Message)"
		}
	}
}

function Start-DependencyServices {
	if ($SkipDependencies) {
		Write-Ava 'Skipping dependency services.'
		return
	}
	foreach ($serviceName in $DependencyServices) {
		$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
		if ($null -eq $service) {
			Write-AvaWarning "Dependency service not found: $serviceName"
			continue
		}
		if ($service.Status -eq 'Running') {
			Write-Ava "$serviceName is already running."
			continue
		}
		try {
			Write-Ava "Starting dependency service: $serviceName"
			Start-Service -Name $serviceName -ErrorAction Stop
			(Get-Service -Name $serviceName).WaitForStatus('Running', '00:00:45')
		} catch {
			Write-AvaWarning "Could not start $serviceName. Run the terminal as Administrator if you need to control Windows services. $($_.Exception.Message)"
		}
	}
}

function Stop-AppServers {
	Stop-PidFileProcess -PidFile (Join-Path $BackendLogDir 'node-backend.pid') -Name 'Node backend'
	Stop-PortProcesses -Ports @(8080) -Name 'AVA backend' -Matcher ${function:Test-BackendProcess}

	Stop-PidFileProcess -PidFile (Join-Path $LlmLogDir 'notiva-ai.pid') -Name 'Notiva AI'
	Stop-PortProcesses -Ports @(8091) -Name 'Notiva AI' -Matcher ${function:Test-NotivaProcess}

	Stop-PidFileProcess -PidFile (Join-Path $LlmLogDir 'llm-server.pid') -Name 'LLM server'
	Stop-PortProcesses -Ports @(8088) -Name 'LLM server' -Matcher ${function:Test-LlmProcess}

	Stop-PidFileProcess -PidFile (Join-Path $LiveKitDir 'azoom-sfu.pid') -Name 'AZOOM SFU'
	Stop-PortProcesses -Ports @(7880, 7881) -Name 'AZOOM SFU' -Matcher ${function:Test-LiveKitProcess}
}

function Start-LiveKit {
	if (Test-PortListening -Port 7880) {
		Write-Ava 'AZOOM SFU is already listening on port 7880.'
		return
	}
	$script = Join-Path $NodeBackendDir 'start_azoom_sfu.ps1'
	Write-Ava 'Starting AZOOM SFU.'
	& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -ProxyPort 8080
	Wait-Port -Name 'AZOOM SFU' -Port 7880 -TimeoutSeconds 60
}

function Start-Backend {
	if (Test-PortListening -Port 8080) {
		Write-Ava 'Node backend is already listening on port 8080.'
		return
	}
	Warn-MissingBackendIntegrations
	if (-not (Test-Path -LiteralPath $NodeBackendDir)) {
		throw "NodeBackend directory is missing: $NodeBackendDir"
	}
	$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
	$nodeExe = if ($nodeCommand) { $nodeCommand.Source } else { 'C:\Program Files\nodejs\node.exe' }
	if (-not (Test-Path -LiteralPath $nodeExe)) {
		throw "Node.js executable was not found. Install Node.js or add node.exe to PATH."
	}
	if (-not (Test-Path -LiteralPath (Join-Path $NodeBackendDir 'node_modules'))) {
		$npmCommand = Get-Command npm -ErrorAction SilentlyContinue
		$npmExe = if ($npmCommand) { $npmCommand.Source } else { 'C:\Program Files\nodejs\npm.cmd' }
		if (-not (Test-Path -LiteralPath $npmExe)) {
			throw "npm was not found. Install Node.js or add npm to PATH."
		}
		Write-Ava 'Installing NodeBackend dependencies.'
		Push-Location $NodeBackendDir
		try {
			& $npmExe install --no-audit --no-fund
		} finally {
			Pop-Location
		}
	}
	New-Item -ItemType Directory -Force -Path $BackendLogDir | Out-Null
	$stdout = Join-Path $BackendLogDir 'node-backend.out.log'
	$stderr = Join-Path $BackendLogDir 'node-backend.err.log'
	$pidFile = Join-Path $BackendLogDir 'node-backend.pid'
	Write-Ava 'Starting Node backend.'
	$process = Start-Process -FilePath $nodeExe `
		-ArgumentList @('src/server.js') `
		-WorkingDirectory $NodeBackendDir `
		-RedirectStandardOutput $stdout `
		-RedirectStandardError $stderr `
		-WindowStyle Hidden `
		-PassThru
	Set-Content -LiteralPath $pidFile -Value $process.Id -Encoding ASCII
	Wait-Port -Name 'Node backend' -Port 8080 -TimeoutSeconds 120
}

function Start-Notiva {
	if (Test-PortListening -Port 8091) {
		Write-Ava 'Notiva AI is already listening on port 8091.'
		return
	}
	New-Item -ItemType Directory -Force -Path $LlmLogDir | Out-Null
	$stdout = Join-Path $LlmLogDir 'notiva-launch.out.log'
	$stderr = Join-Path $LlmLogDir 'notiva-launch.err.log'
	$pidFile = Join-Path $LlmLogDir 'notiva-ai.pid'
	Write-Ava 'Starting Notiva AI.'
	$process = Start-Process -FilePath 'powershell.exe' `
		-ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $LlmDir 'start_notiva_ai.ps1')) `
		-WorkingDirectory $LlmDir `
		-RedirectStandardOutput $stdout `
		-RedirectStandardError $stderr `
		-WindowStyle Hidden `
		-PassThru
	Set-Content -LiteralPath $pidFile -Value $process.Id -Encoding ASCII
	Wait-Port -Name 'Notiva AI' -Port 8091 -TimeoutSeconds 120
}

function Start-Llm {
	if (Test-PortListening -Port 8088) {
		Write-Ava 'LLM server is already listening on port 8088.'
		return
	}
	New-Item -ItemType Directory -Force -Path $LlmLogDir | Out-Null
	$stdout = Join-Path $LlmLogDir 'llm-server.out.log'
	$stderr = Join-Path $LlmLogDir 'llm-server.err.log'
	$pidFile = Join-Path $LlmLogDir 'llm-server.pid'
	Write-Ava 'Starting LLM server.'
	$process = Start-Process -FilePath 'powershell.exe' `
		-ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $LlmDir 'start_server.ps1')) `
		-WorkingDirectory $LlmDir `
		-RedirectStandardOutput $stdout `
		-RedirectStandardError $stderr `
		-WindowStyle Hidden `
		-PassThru
	Set-Content -LiteralPath $pidFile -Value $process.Id -Encoding ASCII
	Wait-Port -Name 'LLM server' -Port 8088 -TimeoutSeconds 180
}

function Start-AppServers {
	Start-LiveKit
	Start-Notiva
	Start-Llm
	Start-Backend

	Wait-HttpReady -Name 'LiveKit' -Url 'http://127.0.0.1:7880' -TimeoutSeconds 30
	Wait-HttpReady -Name 'Notiva AI' -Url 'http://127.0.0.1:8091/docs' -TimeoutSeconds 120
	Wait-HttpReady -Name 'LLM server' -Url 'http://127.0.0.1:8088/v1/models' -TimeoutSeconds 300 -RejectPattern 'Loading model|unavailable_error'
	Wait-HttpReady -Name 'Node backend' -Url 'http://127.0.0.1:8080/api/app-updates/android/latest?currentVersion=0.0.0' -TimeoutSeconds 180
}

function Show-Status {
	$ports = @(5432, 6379, 27017, 7880, 7881, 8080, 8088, 8091)
	$listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
		Where-Object { $_.LocalPort -in $ports } |
		Sort-Object LocalPort
	$rows = foreach ($listener in $listeners) {
		$process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
		[PSCustomObject]@{
			Port = $listener.LocalPort
			PID = $listener.OwningProcess
			Process = $process.ProcessName
		}
	}
	if ($rows) {
		$rows | Format-Table -AutoSize
	} else {
		Write-Ava 'No AVA ports are listening.'
	}

	$services = foreach ($serviceName in $DependencyServices) {
		Get-Service -Name $serviceName -ErrorAction SilentlyContinue
	}
	if ($services) {
		$services | Select-Object Name, Status | Format-Table -AutoSize
	}

	[PSCustomObject]@{
		Integration = 'Notion'
		Configured = Test-NotionConfigured
	} | Format-Table -AutoSize
}

switch ($Action) {
	'start' {
		if (Test-AllServersRunning) {
			Write-Ava 'All AVA servers are already running.'
			Show-Status
			return
		}
		Write-Ava 'Starting all AVA servers.'
		Start-DependencyServices
		Start-AppServers
		Show-Status
	}
	'stop' {
		Write-Ava 'Stopping all AVA servers.'
		Stop-AppServers
		Stop-DependencyServices
		Show-Status
	}
	'restart' {
		Write-Ava 'Restarting all AVA servers.'
		Stop-AppServers
		Stop-DependencyServices
		Start-DependencyServices
		Start-AppServers
		Show-Status
	}
	'status' {
		Show-Status
	}
}
