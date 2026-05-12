param(
    [string]$Remote = "origin",
    [string]$Branch = "flutterflow",
    [string]$WorktreePath = ".flutterflow-worktree"
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $repoRoot

if (-not (Test-Path -LiteralPath ".git")) {
    throw "This workspace is not a Git repository yet. Run git init and add a GitHub remote first."
}

if (-not (git remote | Where-Object { $_ -eq $Remote })) {
    throw "Git remote '$Remote' was not found. Add your GitHub repo first: git remote add origin <repo-url>"
}

git fetch $Remote $Branch

$resolvedWorktree = Join-Path $repoRoot $WorktreePath
if (-not (Test-Path -LiteralPath $resolvedWorktree)) {
    git worktree add $resolvedWorktree "$Remote/$Branch"
} else {
    git -C $resolvedWorktree fetch $Remote $Branch
    git -C $resolvedWorktree checkout $Branch
    git -C $resolvedWorktree reset --hard "$Remote/$Branch"
}

Write-Host "FlutterFlow branch is ready at:"
Write-Host "  $resolvedWorktree"
Write-Host ""
Write-Host "Review generated FlutterFlow code there. Copy only reviewed files into Flutter/lib/src/flutterflow or AVA feature folders."
