param(
	[int]$SignalPort = 7880,
	[int]$RtcTcpPort = 7881,
	[int]$RtcUdpStart = 50000,
	[int]$RtcUdpEnd = 50100,
	[int]$TurnUdpPort = 3478
)

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
	Write-Warning 'Run this script from an elevated PowerShell prompt to add Windows Firewall rules.'
	exit 1
}

$rules = @(
	@{
		Name = 'AVA AZOOM LiveKit Signal TCP'
		Protocol = 'TCP'
		Port = "$SignalPort"
	},
	@{
		Name = 'AVA AZOOM LiveKit ICE TCP'
		Protocol = 'TCP'
		Port = "$RtcTcpPort"
	},
	@{
		Name = 'AVA AZOOM LiveKit ICE UDP Range'
		Protocol = 'UDP'
		Port = "$RtcUdpStart-$RtcUdpEnd"
	},
	@{
		Name = 'AVA AZOOM LiveKit TURN UDP'
		Protocol = 'UDP'
		Port = "$TurnUdpPort"
	}
)

foreach ($rule in $rules) {
	$existing = Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue
	if ($null -eq $existing) {
		New-NetFirewallRule `
			-DisplayName $rule.Name `
			-Direction Inbound `
			-Action Allow `
			-Protocol $rule.Protocol `
			-LocalPort $rule.Port | Out-Null
		Write-Host "Added firewall rule: $($rule.Name) / $($rule.Protocol) $($rule.Port)"
	} else {
		Write-Host "Firewall rule already exists: $($rule.Name)"
	}
}

Write-Host "Router forwarding also needs TCP $SignalPort,$RtcTcpPort and UDP $RtcUdpStart-$RtcUdpEnd,$TurnUdpPort to this server PC."
