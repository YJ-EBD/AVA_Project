$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Venv = Join-Path $Root ".venv-notiva"
$Python = Join-Path $Venv "Scripts\python.exe"
$Pip = Join-Path $Venv "Scripts\pip.exe"
$SystemPython = $env:PYTHON_EXE
if (-not $SystemPython) {
  $Command = Get-Command python -ErrorAction SilentlyContinue
  if ($Command -and $Command.Source -notlike "*WindowsApps*") {
    $SystemPython = $Command.Source
  }
}
if (-not $SystemPython) {
  $Candidate = Join-Path $env:LOCALAPPDATA "Programs\Python\Python311\python.exe"
  if (Test-Path $Candidate) {
    $SystemPython = $Candidate
  }
}
if (-not $SystemPython) {
  throw "Python 3.11+ was not found. Install Python and set PYTHON_EXE to python.exe."
}

if (-not (Test-Path $Python)) {
  & $SystemPython -m venv $Venv
}

& $Python -m pip install --upgrade pip
& $Pip install -r (Join-Path $Root "requirements-notiva.txt")

$env:NOTIVA_WHISPER_MODEL = if ($env:NOTIVA_WHISPER_MODEL) { $env:NOTIVA_WHISPER_MODEL } else { "large-v3" }
$env:NOTIVA_WHISPER_MODEL_DIR = if ($env:NOTIVA_WHISPER_MODEL_DIR) { $env:NOTIVA_WHISPER_MODEL_DIR } else { Join-Path $Root "models\whisper-large-v3" }

Write-Host "Notiva AI Whisper large-v3 dependencies installed."
Write-Host "Model will be downloaded into $env:NOTIVA_WHISPER_MODEL_DIR on first transcription."
