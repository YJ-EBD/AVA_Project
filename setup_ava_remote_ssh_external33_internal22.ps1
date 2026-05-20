$ErrorActionPreference = "Stop"

$sshUser = "ava_ssh"
$externalPort = 33
$internalPort = 22
$extraLocalPort = 33
$configPath = "C:\ProgramData\ssh\sshd_config"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-AsAdministrator {
    $scriptPath = $PSCommandPath
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
}

function Set-OrAppendConfigLine {
    param(
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$Lines,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $updated = $false
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match "^\s*#?\s*$([regex]::Escape($Key))\b") {
            $Lines[$index] = "$Key $Value"
            $updated = $true
            break
        }
    }

    if (-not $updated) {
        $Lines.Add("$Key $Value")
    }
}

function Ensure-FirewallPort {
    param([Parameter(Mandatory = $true)][int]$Port)

    $ruleName = "AVA-OpenSSH-Port-$Port"
    $existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Set-NetFirewallRule -Name $ruleName -Enabled True -Direction Inbound -Action Allow -Profile Any
        Set-NetFirewallPortFilter -AssociatedNetFirewallRule $existing -Protocol TCP -LocalPort $Port
        return
    }

    New-NetFirewallRule `
        -Name $ruleName `
        -DisplayName "AVA OpenSSH Server (Port $Port)" `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $Port `
        -Profile Any | Out-Null
}

if (-not (Test-IsAdministrator)) {
    Write-Host "Administrator permission is required. Requesting elevation..."
    Restart-AsAdministrator
    exit
}

$service = Get-Service sshd -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "OpenSSH Server is not installed. Installing Windows capability..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
}

$user = Get-LocalUser -Name $sshUser -ErrorAction SilentlyContinue
if (-not $user) {
    Write-Host "Creating local SSH user '$sshUser'."
    $password = Read-Host "Enter password for $sshUser" -AsSecureString
    New-LocalUser -Name $sshUser -Password $password -FullName "AVA SSH" -Description "AVA Remote SSH user" | Out-Null
    Add-LocalGroupMember -Group "Users" -Member $sshUser -ErrorAction SilentlyContinue
} else {
    if (-not $user.Enabled) {
        Enable-LocalUser -Name $sshUser
    }
    if (-not $user.PasswordRequired) {
        Write-Host "'$sshUser' currently does not require a password. Setting a password for SSH login."
        $password = Read-Host "Enter password for $sshUser" -AsSecureString
        Set-LocalUser -Name $sshUser -Password $password
        & net.exe user $sshUser /passwordreq:yes | Out-Null
    }
}

if (-not (Test-Path -LiteralPath $configPath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configPath) | Out-Null
    New-Item -ItemType File -Force -Path $configPath | Out-Null
}

$backupPath = "$configPath.ava-external33-internal22-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $configPath -Destination $backupPath -Force

$lines = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $configPath)
for ($index = $lines.Count - 1; $index -ge 0; $index--) {
    if ($lines[$index] -match "^\s*#?\s*Port\b") {
        $lines.RemoveAt($index)
    }
}

$insertIndex = 0
while ($insertIndex -lt $lines.Count -and $lines[$insertIndex].Trim().StartsWith("#")) {
    $insertIndex++
}
$lines.Insert($insertIndex, "Port $extraLocalPort")
$lines.Insert($insertIndex, "Port $internalPort")

Set-OrAppendConfigLine -Lines $lines -Key "ListenAddress" -Value "0.0.0.0"
Set-OrAppendConfigLine -Lines $lines -Key "PasswordAuthentication" -Value "yes"
Set-OrAppendConfigLine -Lines $lines -Key "PermitEmptyPasswords" -Value "no"
Set-OrAppendConfigLine -Lines $lines -Key "PubkeyAuthentication" -Value "yes"

[System.IO.File]::WriteAllLines($configPath, $lines, [System.Text.UTF8Encoding]::new($false))

Ensure-FirewallPort -Port $internalPort
Ensure-FirewallPort -Port $extraLocalPort

Set-Service -Name sshd -StartupType Automatic
Restart-Service -Name sshd -Force
Start-Sleep -Seconds 2

$listeners = Get-NetTCPConnection -LocalPort $internalPort,$extraLocalPort -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,OwningProcess |
    Sort-Object LocalPort

if (-not ($listeners | Where-Object { $_.LocalPort -eq $internalPort })) {
    throw "sshd did not start listening on internal TCP port $internalPort."
}

Write-Host ""
Write-Host "AVA Remote SSH setup completed for router external $externalPort -> internal $internalPort."
Write-Host "Config backup: $backupPath"
Write-Host ""
$listeners | Format-Table -AutoSize
Write-Host ""
Write-Host "Router forwarding should be:"
Write-Host "  WAN TCP $externalPort -> 192.168.0.13 TCP $internalPort"
Write-Host ""
Write-Host "Remote-SSH config stays:"
Write-Host "Host AVA"
Write-Host "    HostName 112.166.136.198"
Write-Host "    User $sshUser"
Write-Host "    Port $externalPort"
Write-Host "    PreferredAuthentications password"
Write-Host "    PubkeyAuthentication no"
