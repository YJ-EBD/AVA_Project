$ErrorActionPreference = "Stop"

$sshPort = 33
$sshUser = "ava_ssh"
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

function Ensure-OpenSshServer {
    $service = Get-Service sshd -ErrorAction SilentlyContinue
    if ($service) {
        return
    }

    Write-Host "OpenSSH Server is not installed. Installing Windows capability..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
}

function Set-OrAppendConfigLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $lines = if (Test-Path -LiteralPath $Path) {
        [System.Collections.Generic.List[string]](Get-Content -LiteralPath $Path)
    } else {
        [System.Collections.Generic.List[string]]::new()
    }

    $updated = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^\s*#?\s*$([regex]::Escape($Key))\b") {
            $lines[$index] = "$Key $Value"
            $updated = $true
            break
        }
    }

    if (-not $updated) {
        $lines.Add("$Key $Value")
    }

    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
}

function Ensure-SshUser {
    $user = Get-LocalUser -Name $sshUser -ErrorAction SilentlyContinue
    if (-not $user) {
        Write-Host "Creating local SSH user '$sshUser'."
        $password = Read-Host "Enter password for $sshUser" -AsSecureString
        New-LocalUser -Name $sshUser -Password $password -FullName "AVA SSH" -Description "AVA Remote SSH user" | Out-Null
        Add-LocalGroupMember -Group "Users" -Member $sshUser -ErrorAction SilentlyContinue
        return
    }

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

function Ensure-FirewallRule {
    $ruleName = "AVA-OpenSSH-Port-$sshPort"
    $existing = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($existing) {
        Set-NetFirewallRule -Name $ruleName -Enabled True -Direction Inbound -Action Allow -Profile Any
        Set-NetFirewallPortFilter -AssociatedNetFirewallRule $existing -Protocol TCP -LocalPort $sshPort
        return
    }

    New-NetFirewallRule `
        -Name $ruleName `
        -DisplayName "AVA OpenSSH Server (Port $sshPort)" `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort $sshPort `
        -Profile Any | Out-Null
}

if (-not (Test-IsAdministrator)) {
    Write-Host "Administrator permission is required. Requesting elevation..."
    Restart-AsAdministrator
    exit
}

Ensure-OpenSshServer
Ensure-SshUser

if (-not (Test-Path -LiteralPath $configPath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configPath) | Out-Null
    New-Item -ItemType File -Force -Path $configPath | Out-Null
}

$backupPath = "$configPath.ava-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item -LiteralPath $configPath -Destination $backupPath -Force

Set-OrAppendConfigLine -Path $configPath -Key "Port" -Value "$sshPort"
Set-OrAppendConfigLine -Path $configPath -Key "ListenAddress" -Value "0.0.0.0"
Set-OrAppendConfigLine -Path $configPath -Key "PasswordAuthentication" -Value "yes"
Set-OrAppendConfigLine -Path $configPath -Key "PermitEmptyPasswords" -Value "no"
Set-OrAppendConfigLine -Path $configPath -Key "PubkeyAuthentication" -Value "yes"

Ensure-FirewallRule

Set-Service -Name sshd -StartupType Automatic
Restart-Service -Name sshd -Force
Start-Sleep -Seconds 2

$listener = Get-NetTCPConnection -LocalPort $sshPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $listener) {
    throw "sshd did not start listening on TCP port $sshPort. Check Windows Event Viewer > OpenSSH logs."
}

Write-Host ""
Write-Host "AVA Remote SSH setup completed."
Write-Host "Local listener: $($listener.LocalAddress):$($listener.LocalPort), PID $($listener.OwningProcess)"
Write-Host "Config backup: $backupPath"
Write-Host ""
Write-Host "VS Code Remote-SSH config:"
Write-Host "Host AVA"
Write-Host "    HostName 112.166.136.198"
Write-Host "    User $sshUser"
Write-Host "    Port $sshPort"
Write-Host "    PreferredAuthentications password"
Write-Host "    PubkeyAuthentication no"
Write-Host ""
Write-Host "Router port forwarding still must point WAN TCP $sshPort to this PC: 192.168.0.13 TCP $sshPort."
