$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $Root ".venv-notiva\Scripts\python.exe"

if (-not (Test-Path $Python)) {
  & (Join-Path $Root "install_whisper_large_v3.ps1")
}

$env:NOTIVA_WHISPER_BATCH_MODEL = if ($env:NOTIVA_WHISPER_BATCH_MODEL) { $env:NOTIVA_WHISPER_BATCH_MODEL } else { "large-v3" }
$env:NOTIVA_WHISPER_REALTIME_MODEL = if ($env:NOTIVA_WHISPER_REALTIME_MODEL) { $env:NOTIVA_WHISPER_REALTIME_MODEL } else { "turbo" }
$env:NOTIVA_WHISPER_MODEL_ROOT = if ($env:NOTIVA_WHISPER_MODEL_ROOT) { $env:NOTIVA_WHISPER_MODEL_ROOT } else { Join-Path $Root "models" }
$env:NOTIVA_WHISPER_DEVICE = if ($env:NOTIVA_WHISPER_DEVICE) { $env:NOTIVA_WHISPER_DEVICE } else { "cpu" }
$env:NOTIVA_WHISPER_COMPUTE_TYPE = if ($env:NOTIVA_WHISPER_COMPUTE_TYPE) { $env:NOTIVA_WHISPER_COMPUTE_TYPE } else { "int8" }
$env:NOTIVA_WHISPER_REALTIME_BEAM_SIZE = if ($env:NOTIVA_WHISPER_REALTIME_BEAM_SIZE) { $env:NOTIVA_WHISPER_REALTIME_BEAM_SIZE } else { "1" }
$env:NOTIVA_WHISPER_BATCH_BEAM_SIZE = if ($env:NOTIVA_WHISPER_BATCH_BEAM_SIZE) { $env:NOTIVA_WHISPER_BATCH_BEAM_SIZE } else { "5" }

$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$ErrorActionPreference = "Continue"
& $Python -m uvicorn notiva_ai_server:app --host 0.0.0.0 --port 8091 `
  *> (Join-Path $LogDir "notiva-ai.log")
