$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Join-Path $Root ".venv-notiva\Scripts\python.exe"
$Audio = Join-Path $Root "notiva_silence.wav"

if (-not (Test-Path $Python)) {
  throw "Notiva AI virtualenv is missing. Run install_whisper_large_v3.ps1 first."
}

& $Python -c "import wave; f=wave.open(r'$Audio','wb'); f.setnchannels(1); f.setsampwidth(2); f.setframerate(16000); f.writeframes(b'\x00\x00'*16000); f.close()"

for ($i = 1; $i -le 10; $i++) {
  $Result = curl.exe -s -X POST -F "file=@$Audio" -F "language=ko" http://127.0.0.1:8091/v1/notiva/transcribe
  if ($LASTEXITCODE -ne 0 -or -not $Result.Contains('"text":""') -or -not $Result.Contains('"segments":[]')) {
    throw "Notiva AI transcription smoke test failed at run $i. Result: $Result"
  }
  Write-Host "Notiva AI silence guard smoke test $i/10 passed."
}
