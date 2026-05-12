param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRelativePath,
    [Parameter(Mandatory = $true)]
    [string]$DestinationRelativePath,
    [string]$WorktreePath = ".flutterflow-worktree"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$worktreeRoot = Join-Path $repoRoot $WorktreePath
$source = Join-Path $worktreeRoot $SourceRelativePath
$destination = Join-Path $repoRoot $DestinationRelativePath

if (-not (Test-Path -LiteralPath $source)) {
    throw "Source file was not found: $source"
}

$resolvedWorktree = (Resolve-Path -LiteralPath $worktreeRoot).Path
$resolvedSource = (Resolve-Path -LiteralPath $source).Path
if (-not $resolvedSource.StartsWith($resolvedWorktree, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Source must stay inside $resolvedWorktree"
}

$destinationParent = Split-Path -Parent $destination
New-Item -ItemType Directory -Force -Path $destinationParent | Out-Null
Copy-Item -LiteralPath $resolvedSource -Destination $destination -Force

Write-Host "Imported:"
Write-Host "  from: $resolvedSource"
Write-Host "  to:   $destination"
