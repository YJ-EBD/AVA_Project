$ErrorActionPreference = "Stop"

$configPath = "C:\ProgramData\ssh\sshd_config"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Start-Process powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`"" `
        -Verb RunAs
    exit
}

Copy-Item -LiteralPath $configPath -Destination "$configPath.port-backup-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force

$rawLines = Get-Content -LiteralPath $configPath
$lines = [System.Collections.Generic.List[string]]::new()
foreach ($line in $rawLines) {
    if ($line -notmatch "^\s*#?\s*Port\b") {
        $lines.Add($line)
    }
}

$lines.Insert(0, "Port 33")
$lines.Insert(0, "Port 22")

function Upsert-Line {
    param([string]$Key, [string]$Value)

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*#?\s*$([regex]::Escape($Key))\b") {
            $lines[$i] = "$Key $Value"
            return
        }
    }
    $lines.Add("$Key $Value")
}

Upsert-Line "ListenAddress" "0.0.0.0"
Upsert-Line "PasswordAuthentication" "yes"
Upsert-Line "PermitEmptyPasswords" "no"
Upsert-Line "PubkeyAuthentication" "yes"

[System.IO.File]::WriteAllLines($configPath, $lines, [System.Text.UTF8Encoding]::new($false))

foreach ($port in 22, 33) {
    $ruleName = "AVA-OpenSSH-Port-$port"
    if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name $ruleName -DisplayName "AVA OpenSSH Server (Port $port)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $port -Profile Any | Out-Null
    } else {
        Set-NetFirewallRule -Name $ruleName -Enabled True -Direction Inbound -Action Allow -Profile Any
    }
}

Set-Service sshd -StartupType Automatic
Restart-Service sshd -Force
Start-Sleep -Seconds 2

Get-Service sshd | Format-Table -AutoSize
Get-NetTCPConnection -LocalPort 22,33 -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,OwningProcess |
    Sort-Object LocalPort |
    Format-Table -AutoSize

Write-Host ""
Write-Host "Done. Router external 33 -> internal 22 now matches this PC."
