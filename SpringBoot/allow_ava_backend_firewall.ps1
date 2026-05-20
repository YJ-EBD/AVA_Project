$ErrorActionPreference = "Stop"

$ruleName = "AVA SpringBoot Backend 8080"
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

if ($null -eq $existingRule) {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort 8080 `
        -Profile Any | Out-Null
} else {
    Set-NetFirewallRule `
        -DisplayName $ruleName `
        -Enabled True `
        -Direction Inbound `
        -Action Allow `
        -Profile Any
    Set-NetFirewallPortFilter `
        -AssociatedNetFirewallRule $existingRule `
        -Protocol TCP `
        -LocalPort 8080
}

Write-Host "AVA SpringBoot backend firewall rule is enabled for TCP 8080."
