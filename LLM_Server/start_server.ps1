$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Server = Join-Path $Root "bin\llama-server.exe"
$Model = Join-Path $Root "models\Qwen_Qwen3.5-27B-Q4_K_M.gguf"

if (-not (Test-Path $Server)) {
    throw "llama-server.exe not found: $Server"
}

if (-not (Test-Path $Model)) {
    throw "Model file not found: $Model"
}

$ExistingListener = Get-NetTCPConnection -LocalPort 8088 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ExistingListener) {
    Write-Host "AVA local LLM server is already listening on port 8088."
    exit 0
}

$ExistingProcess = Get-CimInstance Win32_Process -Filter "Name = 'llama-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
        $commandLine = [string]$_.CommandLine
        $commandLine -like "*Qwen_Qwen3.5-27B-Q4_K_M.gguf*" -or
        $commandLine -match '(^|\s)--port(?:\s+|=)["'']?8088["'']?(\s|$)'
    } |
    Select-Object -First 1
if ($ExistingProcess) {
    Write-Host "AVA local LLM server process is already running. PID: $($ExistingProcess.ProcessId)"
    exit 0
}

$ServerArgs = @(
    "--model", $Model,
    "--host", "127.0.0.1",
    "--port", "8088",
    "--alias", "ava-qwen3.5-27b-q4km",
    "--ctx-size", "40960",
    "--parallel", "10",
    "--n-gpu-layers", "999",
    "--cont-batching",
    "--flash-attn", "on",
    "--cache-type-k", "q4_0",
    "--cache-type-v", "q4_0",
    "--jinja",
    "--metrics"
)

$env:LLAMA_CHAT_TEMPLATE_KWARGS = '{"enable_thinking":false}'

Write-Host "Starting AVA local LLM server..."
Write-Host "Endpoint: http://127.0.0.1:8088/v1/chat/completions"
Write-Host "Model alias: ava-qwen3.5-27b-q4km"
Write-Host ""

& $Server @ServerArgs
