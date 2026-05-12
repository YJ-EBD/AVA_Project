param()

$ErrorActionPreference = "Stop"

$flutterFlowExe = "C:\Program Files\FlutterFlow\flutterflow.exe"
if (-not (Test-Path -LiteralPath $flutterFlowExe)) {
    throw "FlutterFlow Desktop was not found at $flutterFlowExe"
}

Start-Process -FilePath $flutterFlowExe -WorkingDirectory (Split-Path -Parent $flutterFlowExe)
