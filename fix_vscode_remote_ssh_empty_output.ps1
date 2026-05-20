$ErrorActionPreference = "Stop"

$openSshRegistryPath = "HKLM:\SOFTWARE\OpenSSH"
$powershellPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"

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

if (-not (Test-Path -LiteralPath $openSshRegistryPath)) {
    New-Item -Path $openSshRegistryPath -Force | Out-Null
}

New-ItemProperty `
    -Path $openSshRegistryPath `
    -Name DefaultShell `
    -Value $powershellPath `
    -PropertyType String `
    -Force | Out-Null

New-ItemProperty `
    -Path $openSshRegistryPath `
    -Name DefaultShellCommandOption `
    -Value "-c" `
    -PropertyType String `
    -Force | Out-Null

New-ItemProperty `
    -Path $openSshRegistryPath `
    -Name DefaultShellEscapeArguments `
    -Value 0 `
    -PropertyType DWord `
    -Force | Out-Null

Set-Service sshd -StartupType Automatic
Restart-Service sshd -Force
Start-Sleep -Seconds 2

Get-ItemProperty -Path $openSshRegistryPath |
    Select-Object DefaultShell,DefaultShellCommandOption,DefaultShellEscapeArguments |
    Format-List

Get-Service sshd | Format-Table -AutoSize
Get-NetTCPConnection -LocalPort 22,33 -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress,LocalPort,OwningProcess |
    Sort-Object LocalPort |
    Format-Table -AutoSize

Write-Host ""
Write-Host "VS Code Remote-SSH EmptyOutput fix applied."
Write-Host "If the client still shows EmptyOutput, set remote.SSH.remotePlatform AVA to windows on the client PC and retry."
