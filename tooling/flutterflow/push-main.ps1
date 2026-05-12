param(
    [string]$Remote = "origin",
    [string]$Branch = "main"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $repoRoot

git status --short
Write-Host ""
Write-Host "This script pushes the AVA app source branch. It does not push to the FlutterFlow-managed branch."
git push $Remote $Branch
